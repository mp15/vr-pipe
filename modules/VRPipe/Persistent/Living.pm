
=head1 NAME

VRPipe::Persistent::Living - a class to extend from if you can be alive or dead

=head1 SYNOPSIS

*** more documentation to come

=head1 DESCRIPTION

*** more documentation to come

=head1 AUTHOR

Sendu Bala <sb10@sanger.ac.uk>.

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2012 Genome Research Limited.

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

class VRPipe::Persistent::Living extends VRPipe::Persistent {
    use DateTime;
    use EV;
    use AnyEvent;
    
    has 'heartbeat' => (
        is          => 'rw',
        isa         => Datetime,
        coerce      => 1,
        traits      => ['VRPipe::Persistent::Attributes'],
        is_nullable => 1
    );
    
    has 'heartbeat_interval' => (
        is      => 'rw',
        isa     => PositiveInt,
        lazy    => 1,
        builder => '_build_default_heartbeat_interval'
    );
    
    has 'heart' => (
        is      => 'rw',
        isa     => 'Object',
        lazy    => 1,
        builder => '_build_heart',
        handles => { start_beating => 'start', stop_beating => 'stop' }
    );
    
    has 'survival_time' => (
        is      => 'rw',
        isa     => PositiveInt,
        lazy    => 1,
        builder => '_build_default_survival_time'
    );
    
    has 'die_when_murdered' => (
        is      => 'rw',
        isa     => 'Bool',
        default => 1
    );
    
    has '_am_beating' => (
        is      => 'rw',
        isa     => 'Bool',
        default => 0
    );
    
    method _build_default_heartbeat_interval {
        if (VRPipe::Persistent::SchemaBase->database_deployment eq 'testing') {
            return 3;
        }
        else {
            return 60;
        }
    }
    
    method _build_default_survival_time {
        my $interval = $self->heartbeat_interval;
        
        # try and allow for mysql server time being different to our host time,
        # and other related timing vagaries
        my $multiplier;
        if ($interval < 60) {
            $multiplier = 10;
        }
        elsif ($interval < 300) {
            $multiplier = 3;
        }
        else {
            $multiplier = 1;
        }
        
        return $interval * $multiplier;
    }
    
    method _build_heart {
        my $watcher;
        $watcher = EV::timer_ns 0, $self->heartbeat_interval, sub {
            if ($self->die_when_murdered) {
                my $ok = 0;
                if ($self->_still_exists) {
                    $ok = $self->beat_heart;
                }
                if (!$ok) {
                    $self->murder_response;
                }
            }
            else {
                $self->beat_heart || $self->stop_beating;
            }
        };
        return $watcher;
    }
    
    after start_beating {
        $self->_am_beating(1);
    }
    
    after stop_beating {
        $self->_am_beating(0);
    }
    
    around heartbeat (Datetime $datetime?) {
        if ($datetime) {
            return $self->$orig($datetime);
        }
        $self->reselect_values_from_db unless $self->_am_beating;
        return $self->$orig;
    }
    
    method time_since_heartbeat {
        my $heartbeat = $self->heartbeat || return;
        return time() - $heartbeat->epoch;
    }
    
    method alive (Bool :$no_suicide = 0) {
        my $alive = $self->_still_exists;
        if ($alive) {
            my $time_since_heartbeat = $self->time_since_heartbeat;
            return 0 unless defined $time_since_heartbeat;
            $alive = $time_since_heartbeat <= $self->survival_time ? 1 : 0;
        }
        unless ($alive) {
            $self->commit_suicide(no_die => 1) unless $no_suicide;
        }
        return $alive;
    }
    
    method _still_exists {
        my $still_exists = $self->search({ id => $self->id });
        return $still_exists;
    }
    
    method beat_heart {
        $self->heartbeat(DateTime->now());
        $self->update;
        $self->disconnect;
        return 1;
    }
    
    method end_it_all {
        $self->stop_beating;
        $self->delete if $self->_still_exists;
    }
    
    method commit_suicide (Bool :$no_die = 0) {
        $self->end_it_all;
        die "committing suicide\n" unless $no_die;
    }
    
    method murder_response {
        $self->end_it_all;
        EV::unloop;
        die "We were murdered by another process\n";
    }
}

1;
