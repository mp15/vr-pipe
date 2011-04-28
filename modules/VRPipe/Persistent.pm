=head1 NAME

VRPipe::Persistent - base class for objects that want to be persistent in the db

=head1 SYNOPSIS

use VRPipe::Base;

class VRPipe::Artist extends VRPipe::Persistent {
    has 'id' => (is => 'rw',
                 isa => IntSQL[16],
                 traits => ['VRPipe::Persistent::Attributes'],
                 is_auto_increment => 1,
                 is_primary_key => 1);

    has 'name' => (is => 'rw',
                   isa => Varchar[64],
                   traits => ['VRPipe::Persistent::Attributes'],
                   is_key => 1);
                   
    has 'agent' => (is => 'rw',
                    isa => Persistent,
                    coerce => 1,
                    traits => ['VRPipe::Persistent::Attributes'],
                    belongs_to => 'VRPipe::Agent');

    has 'age' => (is => 'rw',
                  isa => IntSQL[3],
                  traits => ['VRPipe::Persistent::Attributes'],
                  default => 0);

    has 'transient_value' => (is => 'rw', isa => 'Str');
    
    __PACKAGE__->make_persistent(has_many => [cds => 'VRPipe::CD']);
}

package main;

use VRPipe::Artist;

# get or create a new artist in the db by supplying all is_keys:
my $bob = VRPipe::Artist->get(name => 'Bob');

=head1 DESCRIPTION

Moose interface to DBIx::Class.

DBIx::Class::MooseColumns is OK, but I prefer my own interface here.

Use VRPipe::Base as normal to setup your class with normal 'has' sugar. For
attributes that you want stored in the database, simply specify
VRPipe::Persistent::Attributes as one of its traits. That trait will allow you
to specificy most DBIx::Class::ResultSource::add_columns args
(http://search.cpan.org/~abraxxa/DBIx-Class-0.08127/lib/DBIx/Class/ResultSource.pm#add_columns)
as properties of your attribute. data_type is not accepted; instead your normal
'isa' determines the data_type. Your isa must be one of IntSQL|Varchar|Bool|
Datetime|Persistent. default_value will also be set from your attribute's
default if it is present and a simple scalar value. is_nullable defaults to
false. A special 'is_key' boolean can be set which results in the column being
indexed and used as part of a multi-column (with other is_key columns)
uniqueness constraint when deciding weather to get or create a new row with
get(). 'is_primary_key' is still used to define the real key, typically reserved
for a single auto increment column in your table. 'allow_key_to_default' will
allow a column to be left out of a call to get() when that column is_key and has
a default or builder, in which case get() will behave as if you had supplied
that column with the default value for that column.

End your class definition with a call to __PACKAGE__->make_persistent, where you
can supply the various relationship types as a hash (key as one of the
relationship methods has_many or many_to_many
(http://search.cpan.org/~abraxxa/DBIx-Class-0.08127/lib/DBIx/Class/Relationship.pm),
value as an array ref of the args you would send to that relationship method, or
an array ref of array refs if you want to specify multiple of the same
relationship type). The other relationship types (belongs_to, has_one and
might_have) can be supplied as properties of attributes, again with an array ref
value, or just a class name string for the default configuration.
You can also supply table_name => $string if you don't want the table_name in
your database to be the same as your class basename.

For end users, get() is a convience method that will call find_or_create on a
ResultSource for your class, if supplied values for all is_key columns (with
the optional exception of any allow_key_to_default columns) and an optional
instance of VRPipe::Persistent::SchemaBase to the schema key (defaults to a
production instance of VRPipe::Persistent::Schema). You can also call
get(id => $id) if you know the real auto-increment key id() for your desired
row.

clone() can be called on an instance of this class, supplying it 1 or more
is_key columns. You'll get back a (potentially) new instance with all the same
is_key column values as the instance you called clone() on, except for the
different values you supplied to clone().

=head1 AUTHOR

Sendu Bala: sb10 at sanger ac uk

=cut

use VRPipe::Base;

class VRPipe::Persistent extends (DBIx::Class::Core, VRPipe::Base::Moose) { # because we're using a non-moose class, we have to specify VRPipe::Base::Moose to get Debuggable
    use MooseX::NonMoose;
    
    __PACKAGE__->load_components(qw/InflateColumn::DateTime/);
    
    has '-result_source' => (is => 'rw', isa => 'DBIx::Class::ResultSource::Table');
    
    method make_persistent ($class: Str :$table_name?, ArrayRef :$has_many?, ArrayRef :$many_to_many?) {
        # decide on the name of the table and initialise
        unless (defined $table_name) {
            $table_name = $class;
            $table_name =~ s/.*:://;
            $table_name = lc($table_name);
        }
        $class->table($table_name);
        
        # determine what columns our table will need from the class attributes
        my @keys;
        my @psuedo_keys;
        my %key_defaults;
        my %relationships = (belongs_to => [], has_one => [], might_have => []);
        my $meta = $class->meta;
        foreach my $attr ($meta->get_all_attributes) {
            my $name = $attr->name;
            
            my $column_info = {};
            if ($attr->does('VRPipe::Persistent::Attributes')) {
                my $vpa_meta = VRPipe::Persistent::Attributes->meta;
                foreach my $vpa_attr ($vpa_meta->get_attribute_list) {
                    next if $vpa_attr =~ /_key/;
                    
                    my $vpa_base = "$vpa_attr";
                    $vpa_base =~ s/.*:://;
                    $vpa_base = lc($vpa_base);
                    if (exists $relationships{$vpa_base}) {
                        my $thing = $attr->$vpa_attr;
                        if ($thing) {
                            my $arg;
                            if (ref($thing)) {
                                $arg = $thing;
                            }
                            else {
                                $arg = [$name => $thing];
                            }
                            push(@{$relationships{$vpa_base}}, $arg);
                        }
                        next;
                    }
                    
                    my $predicate = $vpa_attr.'_was_set';
                    next unless $attr->$predicate();
                    $column_info->{$vpa_attr} = $attr->$vpa_attr;
                }
                
                if ($attr->is_primary_key) {
                    push(@keys, $name);
                }
                elsif ($attr->is_key) {
                    push(@psuedo_keys, $name);
                    if ($attr->allow_key_to_default) {
                        my $default = $attr->_key_default;
                        $key_defaults{$name} = ref $default ? &{$default}($class) : $default;
                    }
                }
            }
            else {
                next;
            }
            
            # add default from our attribute if not already provided
            if (! exists $column_info->{default_value} && defined $attr->default) {
                my $default = $attr->default;
                if (ref($default)) {
                    #$default = &{$default}; #*** we assume it isn't safe to apply some dynamic value to the sql schema table definition default
                    $column_info->{is_nullable} = 1;
                }
                else {
                    $column_info->{default_value} = $default;
                }
                
            }
            
            # determine the type constraint that the database should use
            if ($attr->has_type_constraint) {
                my $t_c = $attr->type_constraint;
                my $cname = $t_c->name;
                
                # $cname needs to be converted to something the database can
                # use when creating the tables, so the following cannot remain
                # hard-coded as it is now for MySQL
                my $size = 0;
                my $is_numeric = 0;
                if ($cname =~ /IntSQL\[(\d+)\]/) {
                    $cname = 'int';
                    $size = $1;
                    $is_numeric = 1;
                }
                elsif ($cname =~ /Varchar\[(\d+)\]/) {
                    $cname = 'varchar';
                    $size = $1;
                }
                elsif ($cname eq 'Bool') {
                    $cname = 'bool';
                }
                elsif ($cname =~ /Datetime/) {
                    $cname = 'datetime';
                }
                elsif ($cname =~ /Persistent/) {
                    $cname = 'int';
                    $size = 16;
                    $is_numeric = 1;
                }
                else {
                    die "unsupported constraint '$cname' for attribute $name in $class\n";
                }
                
                $column_info->{data_type} = $cname;
                $column_info->{size} = $size if $size;
                $column_info->{is_numeric} = $is_numeric;
            }
            else {
                die "attr $name has no constraint in $class\n";
            }
            
            # add the column in DBIx::Class, altering the name of the
            # auto-generated accessor so that we will keep our moose generated
            # accessors with their constraint checking
            my $dbic_name = '_'.$name;
            $column_info->{accessor} = $dbic_name;
            $class->add_column($name => $column_info);
        }
        
        # set the primary key(s)
        $class->set_primary_key(@keys);
        
        # set relationships
        $relationships{has_many} = $has_many || [];
        $relationships{many_to_many} = $many_to_many || [];
        my %accessor_altered;
        foreach my $relationship (qw(belongs_to has_one might_have has_many many_to_many)) { # the order is important
            my $args = $relationships{$relationship};
            unless (ref($args->[0])) {
                $args = [$args];
            }
            
            foreach my $arg (@$args) {
                next unless @$arg;
                $class->$relationship(@$arg);
                $accessor_altered{$arg->[0]} = 1;
            }
        }
        
        # now that dbic has finished creating/altering accessor methods, delete
        # them and replace with moose accessors, to give us moose type
        # constraints
        foreach my $attr ($meta->get_all_attributes) {
            my $name = $attr->name;
            next unless $attr->does('VRPipe::Persistent::Attributes');
            my $dbic_name = '_'.$name;
            
            if ($accessor_altered{$name}) {
                # remove DBIx::Class auto-generated accessor method
                $meta->remove_method($name);
                
                # add back the Moose accessors with their constraints etc.
                $attr->install_accessors;
            }
            
            # make the accessor get and set for DBIx::Class as well
            $meta->add_around_method_modifier($name => sub {
                my $orig = shift;
                my $self = shift;
                
                my $moose_value = $self->$orig();
                $self->discard_changes; # always get fresh from the db, incase another instance of this row was altered and updated
                #my $dbic_value = $self->get_column($name); # we lose Datetime handling if we do this
                my $dbic_value = $self->$dbic_name();
                unless (@_) {
                    # make sure we're in sync with the dbic value
                    if (defined $dbic_value) {
                        $moose_value = $self->$orig($dbic_value);
                    }
                    else {
                        $moose_value = $self->$orig();
                    }
                }
                else {
                    my $value = shift;
                    
                    # first try setting in our Moose accessor, so we can see if
                    # it passes the constraint
                    $self->$orig($value);
                    
                    # now set it in the DBIC accessor
                    #$dbic_value = $self->set_column($name, $value);
                    $self->$dbic_name($value);
                    
                    # we deliberatly do not update in the db so that if the user
                    # is setting multiple accessors, another thread getting this
                    # object won't see a partially updated state. Users must
                    # call ->update manually (or destroy their object)
                    #$self->update;
                    
                    # we do not attempt to return the set value, since we only
                    # ever return the database value, which hasn't been updated
                    # yet without that call to ->update
                }
                
                # if the dbic value is another Persistent object, return
                # that, otherwise prefer the moose value
                if (defined $dbic_value && ref($dbic_value)) {
                    return $dbic_value;
                }
                else {
                    return $moose_value;
                }
            });
        }
        
        # create a get method that expects all the psuedo keys and will get or
        # create the corresponding row in the db
        $meta->add_method('get' => sub {
            my ($self, %args) = @_;
            my $schema = delete $args{schema};
            unless ($schema) {
                eval "use VRPipe::Persistent::Schema;"; # avoid circular usage problems
                $schema = VRPipe::Persistent::Schema->connect;
            }
            
            my $id = delete $args{$keys[0]}; # *** we only support a single real key atm; may further restrict this to being an auto-set column with name 'id'
            if ($id) {
                %args = ($keys[0] => $id);
            }
            else {
                foreach my $key (@psuedo_keys) {
                    unless (defined $args{$key}) {
                        if (defined $key_defaults{$key}) {
                            $args{$key} = $key_defaults{$key};
                        }
                        else {
                            $self->throw("get() must be supplied all non-auto-increment keys (@psuedo_keys); missing $key");
                        }
                    }
                }
            }
            
            my $rs = $schema->resultset("$class");
            my $row;
            try {
                $row = $schema->txn_do(sub {
                    my $return = $rs->find_or_create(%args);
                    
                    # for some reason the result_source has no schema, so
                    # reattach it or inflation will break
                    $return->result_source->schema($schema); 
                    
                    return $return;
                });
            }
            catch ($err) {
                $self->throw("Rollback failed!") if ($err =~ /Rollback failed/);
                $self->throw("Failed to find_or_create: $err");
            }
            
            return $row;
        });
        
        $meta->add_method('clone' => sub {
            my ($self, %args) = @_;
            ref($self) || $self->throw("clone can only be called on an instance");
            $self->throw("The real key cannot be supplied to clone") if $args{$keys[0]};
            
            foreach my $key (@psuedo_keys) {
                unless (defined $args{$key}) {
                    $args{$key} = $self->$key();
                }
            }
            
            return $self->get(%args);
        });
        
        # add indexes for the psuedo key columns
        $meta->add_method('sqlt_deploy_hook' => sub {
            my ($self, $sqlt_table) = @_;
            $sqlt_table->add_index(name => 'psuedo_keys', fields => [@psuedo_keys]);
        });
    }
    
    method DEMOLISH {
        $self->update if $self->in_storage;
    }
}

1;
