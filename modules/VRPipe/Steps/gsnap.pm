
=head1 NAME

VRPipe::Steps::gsnap - a step

=head1 DESCRIPTION

*** more documentation to come

=head1 AUTHOR

NJWalker <nw11@sanger.ac.uk>.

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

class VRPipe::Steps::gsnap with VRPipe::StepRole {
    use File::Basename;
    use Data::Dumper;
    
    method options_definition {
        return { gsnap_exe       => VRPipe::StepOption->create(description => 'path to your bismark executable',                                    optional => 1, default_value => $ENV{GSNAP_EXE}),
                 paired_end      => VRPipe::StepOption->create(description => 'Set to 1 if input files are paired end. Default is for single end.', optional => 1, default_value => '0'),
                 gsnap_db_folder => VRPipe::StepOption->create(description => 'path to your bismark genome folder',                                 optional => 1, default_value => $ENV{GSNAP_DB_FOLDER}) };
    }
    
    method inputs_definition {
        return {
            # sequence file - fastq for now
            fastq_files => VRPipe::StepIODefinition->create(type => 'fq', max_files => -1, description => '1 or more fastq files') };
    }
    
    method body_sub {
        return sub {
            my $self            = shift;
            my $options         = $self->options;
            my $gsnap_exe       = $options->{gsnap_exe};
            my $gsnap_db_folder = $options->{gsnap_db_folder};
            $self->set_cmd_summary(VRPipe::StepCmdSummary->create(exe => 'gsnap', version => VRPipe::StepCmdSummary->determine_version($gsnap_exe . ' --version', 'GSNAP version  (.+) c'), summary => 'gsnap -d gsnap_db_folder input_file'));
            my $req = $self->new_requirements(memory => 8000, time => 1); # more? 16GB RAM? Could be 8GB?
            my @input_file = @{ $self->inputs->{fastq_files} };
            my ($name) = fileparse($input_file[0]->basename, ('.fastq'));
            my ($cmd, $output_file_1, $output_file_2);
            
            #
            $output_file_1 = $self->output_file(
                output_key => 'gsnap_concordant_uniq_sam',
                #basename   => $name . "/$name.concordant_uniq",
                basename => $name . ".concordant_uniq",
                type     => 'txt',
                metadata => $input_file[0]->metadata);
            my $output_file_dir   = $output_file_1->dir->stringify;
            my $input_file_path_1 = $input_file[0]->path;
            my $input_file_path_2 = $input_file[1]->path;
            # deal with gunzip
            $cmd = "$gsnap_exe $input_file_path_1 $input_file_path_2 -d $gsnap_db_folder -t 12 -B 4 -N 1 --npaths=1 --filter-chastity=both --clip-overlap --fails-as-input --quality-protocol=sanger --format=sam --split-output=$output_file_dir/$name";
            
            $self->dispatch([qq[$cmd], $req, { output_files => [$output_file_1] }]);
        };
    
    }

    

    method outputs_definition {
        return { gsnap_concordant_uniq_sam => VRPipe::StepIODefinition->create(type => 'txt', description => 'gsnap mapped sequences files in sam format'), };
    }
    
    method description {
        return "Step for GSNAP mapper";
    }
    
    method post_process_sub {
        return sub { return 1; };
    }
    
    method max_simultaneous {
        return 0;            # meaning unlimited
    }

}








