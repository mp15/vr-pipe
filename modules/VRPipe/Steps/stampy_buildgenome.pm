use VRPipe::Base;

class VRPipe::Steps::stampy_buildgenome with VRPipe::StepRole {
    method options_definition {
        return { reference_fasta => VRPipe::StepOption->get(description => 'absolute path to genome reference file to map against'),
                 stampy_index_options => VRPipe::StepOption->get(description => 'options to stampy -G, excluding the reference fasta file and -G itself',
                                                                 optional => 1),
                 stampy_exe => VRPipe::StepOption->get(description => 'path to your stampy.py executable',
                                                       optional => 1,
                                                       default_value => 'stampy.py') };
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
            
            my $stampy_exe = $options->{stampy_exe};
            my $stampy_opts = $options->{stampy_index_options};
            if ($stampy_opts =~ /$ref|-G|build-genome|-H|build-hash/) {
                $self->throw("stampy_index_options should not include the reference or -G or -H options");
            }
            
            $self->set_cmd_summary(VRPipe::StepCmdSummary->get(exe => 'stampy', version => VRPipe::StepCmdSummary->determine_version($stampy_exe, '^stampy v(\S+)'), summary => 'stampy.py '.$stampy_opts.'-G $ref.fa $ref.fa'));
            
            my $cmd = $stampy_exe.' '.$stampy_opts." -G $ref $ref";
            $self->output_file(output_key => 'stampy_index_stidx_file',
                               output_dir => $ref->dir->stringify,
                               basename => $ref->basename.'.stidx',
                               type => 'bin');
            $self->dispatch([$cmd, $self->new_requirements(memory => 3900, time => 1), {block_and_skip_if_ok => 1}]);
        };
    }
    method outputs_definition {
        return { stampy_index_stidx_file => VRPipe::StepIODefinition->get(type => 'bin', description => 'the file produced by stampy -G') };
    }
    method post_process_sub {
        return sub { return 1; };
    }
    method description {
        return "Part 1 (of 2) of indexing a reference genome fasta file, making it suitable for use in subsequent stampy mapping";
    }
    method max_simultaneous {
        return 0; # meaning unlimited
    }
}

1;
