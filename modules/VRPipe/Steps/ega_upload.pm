use VRPipe::Base;

class VRPipe::Steps::ega_upload extends VRPipe::Steps::java {
	around options_definition {
        return { %{$self->$orig},
                 'ega_upload_jar' => VRPipe::StepOption->get(description => 'path to EGA upload client jar'),
                 'ega_dropbox' => VRPipe::StepOption->get(description => 'EGA dropbox name'),
                 'ega_dropbox_passwd' => VRPipe::StepOption->get(description => 'EGA dropbox password'),
                 'allow_dups' => VRPipe::StepOption->get(description => 'Do not fail the job if file already exists in dropbox',
                                                        optional => 1,
                                                        default_value => 0),
        };
    }
    method inputs_definition {
        return { upload_files => VRPipe::StepIODefinition->get(type => 'bin',
                                                            description => 'files to upload to dropbox , eg bams or vcfs',
                                                            max_files => -1) };
    }
	method body_sub {
		return sub {
			my $self = shift;

			my $options = $self->options;
			$self->handle_standard_options($options);

			my $ega_upload_jar = $options->{'ega_upload_jar'};
			my $ega_dropbox = $options->{'ega_dropbox'};
			my $ega_dropbox_passwd = $options->{'ega_dropbox_passwd'};
			my $allow_dups = $options->{'allow_dups'};

            my $req = $self->new_requirements(memory => 1200, time => 1);
            my $jvm_args = $self->jvm_args($req->memory);

			foreach my $upload_file (@{$self->inputs->{upload_files}}) {
				my $basename = $upload_file->basename;
				my $input_dir = $upload_file->dir;

				my $upload_cmd = "cd $input_dir;" . $self->java_exe . " $jvm_args -jar $ega_upload_jar -p $ega_dropbox $ega_dropbox_passwd $basename";
				my $cmd = "use VRPipe::Steps::ega_upload; VRPipe::Steps::ega_upload->ega_upload('$upload_cmd','$allow_dups');";
				$self->dispatch_vrpipecode($cmd, $req);
			}
		};
	}
    method outputs_definition {
        return { }
    }
    method post_process_sub {
        return sub { return 1; };
    }
    method description {
        return "Uploads files into the EGA dropbox using the EGA upload client application";
    }
    method max_simultaneous {
        return 10;
    }
    
    method ega_upload (ClassName|Object $self: Str $cmd_line, Int $allow_dups) {

        system($cmd_line) && $self->throw("failed to run [$cmd_line]");
        
        my ($input_dir, $upload_file) = $cmd_line =~ /cd (\S+);.* (\S+)$/;

		# Check the ega upload logs
		my @logs = `ls -t $input_dir/upload_log*.log`;
		$self->throw("Cannot find log file at $input_dir\n") unless $logs[0];

		my $ok = 0;
		foreach my $log (@logs) {
			chomp($log);
			my $log_file = VRPipe::File->get(path => $log);
			my $logh = $log_file->openr;
			while (my $line=<$logh>) {
				if ($line =~ /Uploaded file: (\S+)\./) {
					if ($1 eq $upload_file) {
						$ok = 1;
						last;
					}
				}
				if ($line =~ /File: (\S+) already uploaded/ && $allow_dups) {
					if ($1 eq $upload_file) {
						$ok = 1;
						last;
					}
				}
			}
			last if $ok == 1;
		}
		unless ($ok == 1) {
			$self->throw("No succesful upload log for $input_dir/$upload_file\n");
		}
        return 1;
    }
}

1;


