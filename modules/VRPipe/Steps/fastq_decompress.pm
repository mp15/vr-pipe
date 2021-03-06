use VRPipe::Base;

class VRPipe::Steps::fastq_decompress with VRPipe::StepRole {
    
    method options_definition {
        return { };
    }
    method inputs_definition {
        return { compressed_fastq_files => VRPipe::StepIODefinition->get(type => 'fq', description => 'compressed fastq files', max_files => -1) };
    }
    method body_sub {
        return sub {
            my $self = shift;
            
            my $req = $self->new_requirements(memory => 500, time => 1);
            foreach my $fq_file (@{$self->inputs->{compressed_fastq_files}}) {
                my $base = $fq_file->basename;
                $base =~ s/\.gz$//;
                my $fq_meta = $fq_file->metadata;
                my $decompressed_fq_file = $self->output_file(output_key => 'decompressed_fastq_files', basename => $base, type => 'fq', metadata => $fq_meta);
                
                my $cmd = "gunzip -c ".$fq_file->path." > ".$decompressed_fq_file->path;
                $self->dispatch_wrapped_cmd('VRPipe::Steps::fastq_decompress', 'decompress_and_check', [$cmd, $req, {output_files => [$decompressed_fq_file]}]); 
            }
        };
    }
    method outputs_definition {
        return { decompressed_fastq_files => VRPipe::StepIODefinition->get(type => 'fq', description => 'decompressed fastq files', max_files => -1) };
    }
    method post_process_sub {
        return sub { return 1; };
    }
    method description {
        return "Decompresses fastq files";
    }
    method max_simultaneous {
        return 0; # meaning unlimited
    }
    method decompress_and_check (ClassName|Object $self: Str $cmd_line) {
        my ($in_path, $out_path) = $cmd_line =~ /(\S+) > (\S+)$/;
        $in_path || $self->throw("cmd_line [$cmd_line] was not constructed as expected");
        $out_path || $self->throw("cmd_line [$cmd_line] was not constructed as expected");
        
        my $in_file = VRPipe::File->get(path => $in_path);
        my $out_file = VRPipe::File->get(path => $out_path);
        
        unless ($in_file->path =~ /\.gz$/) {
            $in_file->symlink($out_file);
            return 1;
        }
        
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
            $self->throw("cmd [$cmd_line] failed because $actual_reads reads were generated in the output fastq file, yet there were $expected_reads reads in the original fastq file");
        }
    }
}

1;
