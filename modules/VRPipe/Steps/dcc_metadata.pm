use VRPipe::Base;

class VRPipe::Steps::dcc_metadata with VRPipe::StepRole {
    method options_definition {
        return { sequence_index => VRPipe::StepOption->get(description => 'for DCC-style filenames and using input bams with poor headers, provide a DCC sequence.index') };
    }
    method inputs_definition {
        return { bam_files => VRPipe::StepIODefinition->get(type => 'bam', description => 'bam files', max_files => -1,
                                                            metadata => {sample => 'sample name',
                                                                         center_name => 'center name',
                                                                         platform => 'sequencing platform, eg. ILLUMINA|LS454|ABI_SOLID',
                                                                         study => 'name of the study, put in the DS field of the RG header line',
                                                                         population => 'sample population',
                                                                         analysis_group => 'project analysis group',
                                                                         split_sequence => 'chromosomal split',
                                                                         reads => 'total number of reads (sequences)',
                                                                         optional => ['split_sequence'] }) };
    }
    method body_sub {
        return sub {
            my $self = shift;
            my $options = $self->options;
            my $sequence_index = $options->{sequence_index};
            foreach my $bam (@{$self->inputs->{bam_files}}) {
                my $in_path = $bam->path;
                my $ofile = $self->output_file(output_key => 'dcc_ready_bam_files', basename => $bam->basename, type => 'bam', metadata => $bam->metadata);
                my $out_path = $ofile->path;
                my $req = $self->new_requirements(memory => 500, time => 1);
                my $this_cmd = "use VRPipe::Steps::dcc_metadata; VRPipe::Steps::dcc_metadata->check_dcc_metadata(q[$in_path], q[$out_path], sequence_index => q[$sequence_index]);";
                $self->dispatch_vrpipecode($this_cmd, $req, {output_files => [$ofile]});
            }
        };
    }
    method outputs_definition {
        return { dcc_ready_bam_files => VRPipe::StepIODefinition->get(type => 'bam',
                                                                      description => 'a bam file with associated metadata',
                                                                      max_files => -1,
                                                                      metadata => {sample => 'sample name',
                                                                                   center_name => 'center name',
                                                                                   platform => 'sequencing platform, eg. ILLUMINA|LS454|ABI_SOLID',
                                                                                   study => 'name of the study, put in the DS field of the RG header line',
                                                                                   population => 'sample population',
                                                                                   analysis_group => 'project analysis group',
                                                                                   split_sequence => 'chromosomal split',
                                                                                   reads => 'total number of reads (sequences)',
                                                                                   optional => ['split_sequence'] }) };
    }
    method post_process_sub {
        return sub {
            return 1;
        };
    }
    method description {
        return "Check the metadata in the bam header, vrpipe and the sequence index are all in agreement and the bam has the expected number of reads.";
    }
    method max_simultaneous {
        return 0; # meaning unlimited
    }

    method check_dcc_metadata (ClassName|Object $self: Str|File $bam!, Str|File $symlink!, Str|File :$sequence_index!) {
        unless (ref($bam) && ref($bam) eq 'VRPipe::File') {
            $bam = VRPipe::File->get(path => file($bam));
        }
        unless (ref($symlink) && ref($symlink) eq 'VRPipe::File') {
            $symlink = VRPipe::File->get(path => file($symlink));
        }
        my $meta = $bam->metadata;
        
        my $bp = VRPipe::Parser->create('bam', {file => $bam});
        my %readgroup_info = $bp->readgroup_info();
        $bp->close;
        
        $bam->disconnect;
        
        my $sip = VRPipe::Parser->create('sequence_index', {file => $sequence_index});
        
        my @fails;
        while (my ($rg, $info) = each %readgroup_info) {
            my $sample = $sip->lane_info($rg, 'SAMPLE_NAME');
            my $center = $sip->lane_info($rg, 'CENTER_NAME');
            my $platform = $sip->lane_info($rg, 'INSTRUMENT_PLATFORM');
            my $study = $sip->lane_info($rg, 'STUDY_ID');
            my $population = $sip->lane_info($rg, 'POPULATION');
            my $ag = $sip->lane_info($rg, 'ANALYSIS_GROUP');
            
            unless ($meta->{sample} eq $info->{SM} && $meta->{sample} eq $sample) {
                push @fails, "sample metadata in db, bam header and sequence index do not agree: $$meta{sample}, $$info{SM}, $sample";
            }
            unless ($meta->{center_name} =~ /$$info{CN}/ && $meta->{center_name} =~ /$center/ && $info->{CN} eq $center) {
                push @fails, "center_name metadata in db, bam header and sequence index do not agree: $$meta{center_name}, $$info{CN}, $center";
            }
            unless ($meta->{platform} eq $info->{PL} && $meta->{platform} eq $platform) {
                push @fails, "platform metadata in db, bam header and sequence index do not agree: $$meta{platform}, $$info{PL}, $platform";
            }
            unless ($meta->{study} =~ /$$info{DS}/ && $meta->{study} =~ /$study/ && $info->{DS} eq $study) {
                push @fails, "study metadata in db, bam header and sequence index do not agree: $$meta{study}, $$info{DS}, $study";
            }
            unless ($meta->{population} eq $population) {
                push @fails, "population metadata in db and and sequence index do not agree: $$meta{population}, $population";
            }
            unless ($meta->{analysis_group} eq $ag) {
                push @fails, "analysis_group metadata in db and and sequence index do not agree: $$meta{analysis_group}, $ag";
            }
        }
        
        my $expected_reads = $meta->{reads};
        my $actual_reads = $bam->num_records;
        
        unless ($expected_reads == $actual_reads) {
            push @fails, "Expected reads $expected_reads not equal to actual reads $actual_reads for file ".$bam->path;
        }
        
        if (@fails) {
            $self->throw(join "\n", @fails);
        } else {
            $bam->symlink($symlink);
            return 1;
        }
    }
}

1;
