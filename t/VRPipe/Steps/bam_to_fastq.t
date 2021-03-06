#!/usr/bin/env perl
use strict;
use warnings;
use Path::Class;

BEGIN {
    use Test::Most tests => 9;
    use VRPipeTest (required_env => [qw(VRPIPE_TEST_PIPELINES SAMTOOLS)]);
    use TestPipelines;
    
    use_ok('VRPipe::Steps::bam_to_fastq');
    use_ok('VRPipe::Parser');
}

my ($output_dir, $pipeline, $step) = create_single_step_pipeline('bam_to_fastq', 'bam_files');
is_deeply [$step->id, $step->description], [1, 'Converts bam files to fastq files'], 'bam_to_fastq step created and has correct description';

# pipeline requires certain metadata on the input bams, so we just manually set that now
VRPipe::File->get(path => file(qw(t data 2822_6.pe.bam))->absolute, metadata => {lane => '2822_6',
                                                                                 reads => 400,
                                                                                 bases => 23000,
                                                                                 forward_reads => 200,
                                                                                 reverse_reads => 200,
                                                                                 paired => 1});
VRPipe::File->get(path => file(qw(t data 2822_6.improved.pe.bam))->absolute, metadata => {lane => '2822_6',
                                                                                          reads => 400,
                                                                                          bases => 23000,
                                                                                          forward_reads => 200,
                                                                                          reverse_reads => 200,
                                                                                          paired => 1});

my $setup = VRPipe::PipelineSetup->get(name => 'btq_setup',
                                       datasource => VRPipe::DataSource->get(type => 'fofn', method => 'all', source => file(qw(t data datasource.btf_fofn))->absolute),
                                       output_root => $output_dir,
                                       pipeline => $pipeline,
                                       options => {});
 
my @fastqs;
for my $j (1, 2) {
    foreach my $i (1, 2) {
        my @output_subdirs = output_subdirs($j);
        push(@fastqs, file(@output_subdirs, '1_bam_to_fastq', "2822_6.$i.fastq"));
    }
}
ok handle_pipeline(@fastqs), 'bam_to_fastq pipeline ran ok, generating the expected fastqs';

is_deeply read_fastq(file(qw(t data 2822_6_1.fastq))->absolute), read_fastq($fastqs[0]), 'forward fastq had same data as original forward fastq the input bam was mapped from';
is_deeply read_fastq(file(qw(t data 2822_6_2.fastq))->absolute), read_fastq($fastqs[1]), 'reverse fastq had same data as original reverse fastq the input bam was mapped from';
is_deeply read_fastq(file(qw(t data 2822_6_1.fastq))->absolute), read_fastq($fastqs[2]), 'forward fastq from improved bam had same data as original forward fastq the input bam was mapped from';
is_deeply read_fastq(file(qw(t data 2822_6_2.fastq))->absolute), read_fastq($fastqs[3]), 'reverse fastq from improved bam had same data as original reverse fastq the input bam was mapped from';

my $fmeta = VRPipe::File->get(path => $fastqs[0])->metadata;
is_deeply [$fmeta->{reads}, $fmeta->{bases}, $fmeta->{avg_read_length}], [200, 12200, '61.00'], 'basic metadata is correct for the forward fastq';

finish;

sub read_fastq {
    my $path = shift;
    my $pars = VRPipe::Parser->create('fastq', {file => VRPipe::File->get(path => $path)});
    
    my %data;
    my $pr = $pars->parsed_record();
    while ($pars->next_record()) {
        $data{$pr->[0]} = [$pr->[1], $pr->[2]];
    }
    return \%data;
}