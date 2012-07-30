
=head1 NAME

VRPipe::Pipelines::gatk_genotype - a pipeline

=head1 DESCRIPTION

Runs the GATK universal genotyper, generating indexed VCF files from a BAM datasource.

=head1 AUTHOR

Chris Joyce <cj5@sanger.ac.uk>.

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

class VRPipe::Pipelines::gatk_genotype with VRPipe::PipelineRole {
    method name {
        return 'gatk_genotype';
    }
    
    method _num_steps {
        return 2;
    }
    
    method description {
        return 'Run gatk universal genotyper';
    }
    
    method steps {
        $self->throw("steps cannot be called on this non-persistent object");
    }
    
    method _step_list {
        return ([
             VRPipe::Step->get(name => 'gatk_genotype'), #1
             VRPipe::Step->get(name => 'vcf_index'),     #2
            ],
            [VRPipe::StepAdaptorDefiner->new(from_step => 0, to_step => 1, to_key => 'bam_files'), VRPipe::StepAdaptorDefiner->new(from_step => 1, to_step => 2, from_key => 'vcf_files', to_key => 'vcf_files'),],
            [],);
    }
}

1;
