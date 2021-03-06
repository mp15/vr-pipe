use VRPipe::Base;

class VRPipe::Steps::vcf_stats with VRPipe::StepRole {
	method options_definition {
        return { 'vcf-stats_options' => VRPipe::StepOption->get(description => 'vcf-stats options'),
			'vcf-stats_exe' => VRPipe::StepOption->get(description => 'path to vcf-stats executable',
					optional => 1,
					default_value => 'vcf-stats') };
	}
	method inputs_definition {
		return { vcf_files => VRPipe::StepIODefinition->get(type => 'vcf',
				description => 'vcf files',
				max_files => -1) };
	}
	method body_sub {
		return sub {
			my $self = shift;

			my $options = $self->options;
			my $stats_exe = $options->{'vcf-stats_exe'};
            my $stats_opts = $options->{'vcf-stats_options'};
			my $cat_exe;

			my $req = $self->new_requirements(memory => 500, time => 1);
			foreach my $vcf_file (@{$self->inputs->{vcf_files}}) {
				my $basename = $vcf_file->basename;
				if ($basename =~ /\.vcf.gz$/) {
					$cat_exe = 'zcat';
				}
				else {
					$cat_exe = 'cat';
				}
				$basename .= '.stats';

				my $stats_file = $self->output_file(output_key => 'stats_file', basename => $basename, type => 'txt');

				my $input_path = $vcf_file->path;
				my $output_path = $stats_file->path;

				my $this_cmd = "$cat_exe $input_path | $stats_exe $stats_opts > $output_path";

				$self->dispatch_wrapped_cmd('VRPipe::Steps::vcf_stats', 'vcf_stats', [$this_cmd, $req, {output_files => [$stats_file]}]);
			}
		};
	}
	method outputs_definition {
		return { stats_file => VRPipe::StepIODefinition->get(type => 'txt',
				description => 'a vcf stats file',
				max_files => -1) };
	}
	method post_process_sub {
		return sub { return 1; };
	}
	method description {
		return "Generate stats file for input VCFs";
	}
	method max_simultaneous {
		return 0; # meaning unlimited
	}

	method vcf_stats (ClassName|Object $self: Str $cmd_line) {
		my ($input_path, $output_path) = $cmd_line =~ /^\S+ (\S+) .* (\S+)$/;
		my $input_file = VRPipe::File->get(path => $input_path);

		$input_file->disconnect;
		system($cmd_line) && $self->throw("failed to run [$cmd_line]");

		my $output_file = VRPipe::File->get(path => $output_path);
		$output_file->update_stats_from_disc;
		my $output_lines = $output_file->lines;

		unless ($output_lines > 0) {
			$output_file->unlink;
			$self->throw("no data in output stats file");
		}
		else {
			return 1;
		}
	}
}

1;
