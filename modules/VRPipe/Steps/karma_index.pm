use VRPipe::Base;

class VRPipe::Steps::karma_index with VRPipe::StepRole {
    method options_definition {
        return { reference_fasta => VRPipe::StepOption->get(description => 'absolute path to genome reference file to map against'),
                 karma_index_options => VRPipe::StepOption->get(description => 'options to karma create, excluding the reference fasta file', optional => 1, default_value => '-i -w 15'),
                 karma_exe => VRPipe::StepOption->get(description => 'path to your karma executable', optional => 1, default_value => 'karma') };
    }
    method inputs_definition {
        return { };
    }
    method body_sub {
        return sub {
            my $self = shift;
            my $options = $self->options;
            my $ref = Path::Class::File->new($options->{reference_fasta});
            $self->throw("reference_fasta must be an absolute path") unless $ref->is_absolute;
            
            my $karma_exe = $options->{karma_exe};
            my $opts = $options->{karma_index_options};
            if ($opts =~ /$ref|create/) {
                $self->throw("karma_index_options should not include the reference or create subcommand");
            }
            
            $self->set_cmd_summary(VRPipe::StepCmdSummary->get(exe => 'karma', 
                                                               version => VRPipe::StepCmdSummary->determine_version($karma_exe, 'version (.+)\.$'), 
                                                               summary => 'karma create '.$opts.' $reference_fasta'));
            
            my $basename = $ref->basename;
            $basename =~ s/\.fa(sta)?$//;
            my ($w) = $opts =~ m/-w (\d+)/;
            my ($o) = $opts =~ m/-O (\d+)/;
            my $space = ($opts =~ /-c/) ? 'cs' : 'bs';
            my $i = ($opts =~ /-i/) ? 1 : 0;
            $w ||= 15;
            $o ||= 5000;

            $self->output_file(output_key => 'karma_index_binary_files', output_dir => $ref->dir->stringify, basename => "$basename-$space.umfa", type => 'bin');
            if ($i) {
                foreach my $suffix (qw(umwihi umwiwp umwhl umwhr)) {
                    $self->output_file(output_key => 'karma_index_binary_files', output_dir => $ref->dir->stringify, basename => "$basename-$space.$w.$o.$suffix", type => 'bin');
                }
            }
            
            my $cmd = qq[$karma_exe create $opts $ref];
            $self->dispatch([$cmd, $self->new_requirements(memory => 31000, time => 1), {block_and_skip_if_ok => 1}]);
        };
    }
    method outputs_definition {
        return { karma_index_binary_files => VRPipe::StepIODefinition->get(type => 'bin', description => 'the binary index files produced by karma create', min_files => 1, max_files => 5) };
    }
    method post_process_sub {
        return sub { return 1; };
    }
    method description {
        return 'Indexes a reference genome fasta file, making it suitable for use in subsequent karma mapping';
    }
    method max_simultaneous {
        return 0; # meaning unlimited
    }
}

1;
