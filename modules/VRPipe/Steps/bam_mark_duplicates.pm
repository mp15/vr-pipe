use VRPipe::Base;

class VRPipe::Steps::bam_mark_duplicates extends VRPipe::Steps::picard {
    around options_definition {
        return { %{$self->$orig},
                 markdup_options => VRPipe::StepOption->get(description => 'command line options for Picard MarkDuplicates', optional => 1, default_value => 'ASSUME_SORTED=TRUE METRICS_FILE=/dev/null VALIDATION_STRINGENCY=SILENT'),
                };
    }
    method inputs_definition {
        return { bam_files => VRPipe::StepIODefinition->get(type => 'bam', max_files => -1, description => '1 or more coordinate-sorted bam files') };
    }
    method body_sub {
        return sub {
            my $self = shift;
            my $options = $self->options;
            $self->handle_standard_options($options);
            my $markdup_jar = $self->jar('MarkDuplicates.jar');
            
            my $markdup_opts = $options->{markdup_options};
            
            $self->set_cmd_summary(VRPipe::StepCmdSummary->get(exe => 'picard', 
                                   version => $self->picard_version(),
                                   summary => 'java $jvm_args -jar MarkDuplicates.jar INPUT=$bam_file OUTPUT=$markdup_bam_file '.$markdup_opts));
            
            my $req = $self->new_requirements(memory => 5800, time => 2);
            foreach my $bam (@{$self->inputs->{bam_files}}) {
                my $bam_base = $bam->basename;
                my $bam_meta = $bam->metadata;
                my $markdup_base = $bam_base;
                $markdup_base =~ s/bam$/markdup.bam/;
                my $markdup_bam_file = $self->output_file(output_key => 'markdup_bam_files',
                                                  basename => $markdup_base,
                                                  type => 'bam',
                                                  metadata => $bam_meta);
                
                my $temp_dir = $options->{tmp_dir} || $markdup_bam_file->dir;
                my $jvm_args = $self->jvm_args($req->memory, $temp_dir);
                
                my $this_cmd = $self->java_exe." $jvm_args -jar $markdup_jar INPUT=".$bam->path." OUTPUT=".$markdup_bam_file->path." $markdup_opts";
                $self->dispatch_wrapped_cmd('VRPipe::Steps::bam_mark_duplicates', 'markdup_and_check', [$this_cmd, $req, {output_files => [$markdup_bam_file]}]); 
            }
        };
    }
    method outputs_definition {
        return { markdup_bam_files => VRPipe::StepIODefinition->get(type => 'bam',max_files => -1,description => 'a bam file with duplicates marked') };
    }
    method post_process_sub {
        return sub { return 1; };
    }
    method description {
        return "Mark duplicates in a bam files using picard";
    }
    method max_simultaneous {
        return 0; # meaning unlimited
    }
    method markdup_and_check (ClassName|Object $self: Str $cmd_line) {
        my ($in_path, $out_path) = $cmd_line =~ /INPUT=(\S+) OUTPUT=(\S+)/;
        $in_path || $self->throw("cmd_line [$cmd_line] was not constructed as expected");
        $out_path || $self->throw("cmd_line [$cmd_line] was not constructed as expected");
        
        my $in_file = VRPipe::File->get(path => $in_path);
        my $out_file = VRPipe::File->get(path => $out_path);
        
        $in_file->disconnect;
        system($cmd_line) && $self->throw("failed to run [$cmd_line]");
        
        $out_file->update_stats_from_disc(retries => 3);
        my $expected_reads = $in_file->metadata->{reads} || $in_file->num_records;
        my $actual_reads = $out_file->num_records;
        
        if ($actual_reads == $expected_reads) {
            return 1;
        }
        else {
            $out_file->unlink;
            $self->throw("cmd [$cmd_line] failed because $actual_reads reads were generated in the output bam file, yet there were $expected_reads reads in the original bam file");
        }
    }
}

1;
