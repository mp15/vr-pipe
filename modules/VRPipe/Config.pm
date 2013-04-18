
=head1 NAME

VRPipe::Config - read/writer for site-wide config details

=head1 SYNOPSIS
    
    use VRPipe::Config;
    
    my $vrp_config = VRPipe::Config->new();
    
    my $production_dbtype = $vrp_config->production_dbtype;

=head1 DESCRIPTION

This module defines the site-wide configuration options that many VRPipe
classes need to function and blindly expect to be defined. This module is
supposed to be used, and all the necessary options defined by the user, during
the initial build process. See Build.PL.

It is implemented using L<VRPipe::Base::Configuration>; see that module for
more details beyond simply getting config option values as shown in the
synopsis.

=head1 AUTHOR

Sendu Bala <sb10@sanger.ac.uk>.

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2011 Genome Research Limited.

This file is part of VRPipe.

VRPipe is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program. If not, see L<http://www.gnu.org/licenses/>.

=cut

use VRPipe::Base;

class VRPipe::Config {
    use VRPipe::Base::Configuration;
    use File::Which qw(which);
    use Cwd 'abs_path';
    
    # we will suggest a default port that is randomly chosen from the "dynamic
    # range" block of ports 49152-65535, minus 20 to allow user to then have
    # multiple test server ports that are increments of their production port
    my $default_port = int(rand(16364)) + 49152;
    
    my $question_number = 0;
    
    has schema_directory => (
        is              => 'rw',
        question        => 'Where should schema files be stored to enable schema upgrades?',
        env             => 'VRPIPE_SCHEMADIR',
        question_number => ++$question_number
    );
    
    has production_dbtype => (
        is              => 'rw',
        question        => 'What DRM should be used for production?',
        default         => 'mysql',
        env             => 'DBI_DRIVER',
        valid           => [qw(mysql postgres sqlite)],
        question_number => ++$question_number
    );
    
    has production_dbname => (
        is              => 'rw',
        question        => 'What is the name of your production database?',
        builder         => '_build_production_dbname',
        question_number => ++$question_number
    );
    
    has production_dbhost => (
        is              => 'rw',
        question        => 'What host is your production database on?',
        skip            => '_skip_based_on_production_db',
        default         => 'localhost',
        env             => 'VRTRACK_HOST',
        question_number => ++$question_number
    );
    
    has production_dbport => (
        is              => 'rw',
        question        => 'What port is your production database accessed with?',
        skip            => '_skip_based_on_production_db',
        builder         => '_build_production_dbport',
        env             => 'VRTRACK_PORT',
        question_number => ++$question_number
    );
    
    has production_username => (
        is              => 'rw',
        question        => 'What username is used to connect to your production database?',
        skip            => '_skip_based_on_production_db',
        default         => '',
        env             => 'VRTRACK_RW_USER',
        question_number => ++$question_number
    );
    
    has production_password => (
        is              => 'rw',
        question        => 'What password is used to connect to your production database?',
        skip            => '_skip_based_on_production_db',
        default         => '',
        env             => 'VRTRACK_PASSWORD',
        secure          => 1,
        question_number => ++$question_number
    );
    
    has testing_dbtype => (
        is              => 'rw',
        question        => 'What DRM should be used for testing?',
        default         => 'sqlite',
        valid           => [qw(sqlite mysql postgres)],
        question_number => ++$question_number
    );
    
    has testing_dbname => (
        is              => 'rw',
        question        => 'What is the name of your testing database?',
        builder         => '_build_test_dbname',
        question_number => ++$question_number
    );
    
    has testing_dbhost => (
        is              => 'rw',
        question        => 'What host is your testing database on?',
        skip            => '_skip_based_on_test_db',
        default         => 'localhost',
        question_number => ++$question_number
    );
    
    has testing_dbport => (
        is              => 'rw',
        question        => 'What port is your testing database accessed with?',
        skip            => '_skip_based_on_test_db',
        builder         => '_build_test_dbport',
        question_number => ++$question_number
    );
    
    has testing_username => (
        is              => 'rw',
        question        => 'What username is used to connect to your testing database?',
        skip            => '_skip_based_on_test_db',
        default         => '',
        env             => 'DBI_USER',
        question_number => ++$question_number
    );
    
    has testing_password => (
        is              => 'rw',
        question        => 'What password is used to connect to your testing database?',
        skip            => '_skip_based_on_test_db',
        default         => '',
        env             => 'DBI_PASS',
        secure          => 1,
        question_number => ++$question_number
    );
    
    has production_scheduler => (
        is              => 'rw',
        question        => 'What job scheduler should be used for production?',
        default         => 'LSF',
        valid           => [qw(LSF local)],
        question_number => ++$question_number
    );
    
    has testing_scheduler => (
        is              => 'rw',
        question        => 'What job scheduler should be used for testing?',
        default         => 'local',
        valid           => [qw(LSF local)],
        question_number => ++$question_number
    );
    
    has production_logging_directory => (
        is              => 'rw',
        question        => 'What directory should production logs, job STDOUT/ERR and temp files be stored in? (must be visible to all nodes)',
        question_number => ++$question_number
    );
    
    has testing_logging_directory => (
        is              => 'rw',
        question        => 'What directory should testing logs, job STDOUT/ERR and temp files be stored in? (must be visible to all nodes)',
        question_number => ++$question_number
    );
    
    has production_interface_port => (
        is              => 'rw',
        question        => 'What port will the VRPipe interface be accessible on, when accessing your production database?',
        default         => $default_port,
        question_number => ++$question_number
    );
    
    has testing_interface_port => (
        is              => 'rw',
        question        => 'What port will the VRPipe interface be accessible on, when accessing your testing database?',
        default         => $default_port + 1,
        question_number => ++$question_number
    );
    
    has production_redis_port => (
        is              => 'rw',
        question        => 'What port should the production redis-server listen on?',
        default         => $default_port - 1,
        question_number => ++$question_number
    );
    
    has testing_redis_port => (
        is              => 'rw',
        question        => 'What port should the testing redis-server listen on?',
        default         => $default_port - 2,
        question_number => ++$question_number
    );
    
    has server_umask => (
        is              => 'rw',
        question        => 'When the VRPipe server runs, what should its file creation mask (umask) be?',
        default         => 0,
        question_number => ++$question_number
    );
    
    has server_uid => (
        is              => 'rw',
        question        => 'When the VRPipe server runs, what user id should it run as?',
        default         => $<,
        question_number => ++$question_number
    );
    
    has email_domain => (
        is              => 'rw',
        question        => 'When the VRPipe server needs to email users, what domain can be used to form valid email addresses with their usernames?',
        question_number => ++$question_number
    );
    
    has admin_user => (
        is              => 'rw',
        question        => 'When the VRPipe server encounters problems, what user should be emailed?',
        default         => 'root',
        question_number => ++$question_number
    );
    
    has exec_shell => (
        is       => 'rw',
        question => 'When VRPipe executes commands with exec(), what shell should be used (avoid the use of dash on Ubuntu, which is its default sh)?',
        default  => sub {
            my $shell = which('bash') || which('sh');
            if ($shell) { $shell = abs_path($shell); undef $shell if $shell =~ /dash$/ }
            return $shell || '';
        },
        question_number => ++$question_number
    );
    
    method _get_dbtype (Str $prefix) {
        my $method = $prefix . '_dbtype';
        return $self->$method();
    }
    
    method _skip_based_on_db (Str $prefix) {
        my $dbtype = $self->_get_dbtype($prefix);
        if ($dbtype eq 'sqlite') {
            return 1;
        }
        return 0;
    }
    
    method _skip_based_on_test_db {
        return $self->_skip_based_on_db('testing');
    }
    
    method _skip_based_on_production_db {
        return $self->_skip_based_on_db('production');
    }
    
    method _default_based_on_db (Str $prefix, Str $field) {
        my $dbtype = $self->_get_dbtype($prefix);
        if ($field eq 'dbname') {
            if ($dbtype eq 'sqlite') {
                return '~/.vrpipe.db';
            }
            else {
                return;
            }
        }
        elsif ($field eq 'dbport') {
            if ($dbtype eq 'mysql') {
                return '3306';
            }
            elsif ($dbtype eq 'postgres') {
                return '5432';
            }
        }
    }
    
    method _default_based_on_test_db (Str $field) {
        return $self->_default_based_on_db('testing', $field);
    }
    
    method _default_based_on_production_db (Str $field) {
        return $self->_default_based_on_db('production', $field);
    }
    
    method _build_production_dbname {
        return $self->_default_based_on_production_db('dbname');
    }
    
    method _build_test_dbname {
        return $self->_default_based_on_test_db('dbname');
    }
    
    method _build_test_dbport {
        return $self->_default_based_on_test_db('dbport');
    }
    
    method _build_production_dbport {
        return $self->_default_based_on_production_db('dbport');
    }
}

1;
