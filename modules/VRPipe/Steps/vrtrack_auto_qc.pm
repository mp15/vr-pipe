use VRPipe::Base;

class VRPipe::Steps::vrtrack_auto_qc extends VRPipe::Steps::vrtrack_update {
    use VRPipe::Parser;
    
    around options_definition {
	return { %{$self->$orig},
		 auto_qc_gtype_regex => VRPipe::StepOption->get(description => 'If the bam_genotype_checking pipeline was run, providing a gtype_analysis metadata key, provide a regular expression to choose acceptable status values',
                                                                optional => 1,
                                                                default_value => '^confirmed'),
		 auto_qc_mapped_base_percentage => VRPipe::StepOption->get(description => 'Minimum percentage of mapped bases',
                                                                           optional => 1,
                                                                           default_value => 90),
		 auto_qc_duplicate_read_percentage => VRPipe::StepOption->get(description => 'Maximum percentage of duplicate reads',
                                                                              optional => 1,
                                                                              default_value => 8),
		 auto_qc_mapped_reads_properly_paired_percentage => VRPipe::StepOption->get(description => 'Minimum percentage of the reads that are mapped which are also properly paired',
											    optional => 1,
											    default_value => 80),
		 auto_qc_error_rate => VRPipe::StepOption->get(description => 'Maximum allowed error rate',
                                                               optional => 1,
                                                               default_value => 0.02),
		 auto_qc_insert_peak_window => VRPipe::StepOption->get(description => 'A percentage of the insert size peak; this will be used get an acceptable range of insert sizes',
								       optional => 1,
								       default_value => 25),
		 auto_qc_insert_peak_reads => VRPipe::StepOption->get(description => 'The minimum percentage of reads that must have an insert size within the auto_qc_insert_peak_window',
								      optional => 1,
								      default_value => 80),
		 auto_qc_max_ins_to_del_ratio => VRPipe::StepOption->get(description => 'Maximum insert to deletion ratio',
									 optional => 1,
									 default_value => '1.0') };
    }
    method inputs_definition {
        return { bam_files => VRPipe::StepIODefinition->get(type => 'bam', 
                                                            description => 'bam files', 
                                                            max_files => -1,
                                                            metadata => {lane => 'lane name (a unique identifer for this sequencing run, aka read group)'}),
                 bamcheck_files => VRPipe::StepIODefinition->get(type => 'txt', 
							  	 description => 'bamcheck files', 
								 max_files => -1,
								 metadata => {lane => 'lane name (a unique identifer for this sequencing run, aka read group)'}) };
    }
    method body_sub {
        return sub {
            my $self = shift;
	    my $opts = $self->options;
	    my $db = $opts->{vrtrack_db};
            my $req = $self->new_requirements(memory => 500, time => 1);
	    
	    # group the bam file with its bamcheck file according to lane; the
	    # bamcheck file might have been made for a different bam (eg.
	    # imported bam, whilst the input bam is an improved bam), so we
	    # can't use source_bam metadata here
	    my %by_lane;
	    foreach my $file (@{$self->inputs->{bam_files}}, @{$self->inputs->{bamcheck_files}}) {
		push(@{$by_lane{$file->metadata->{lane}}}, $file->path);
		my $lane = $file->metadata->{lane};
	    }
	    
            while (my ($lane, $files) = each %by_lane) {
		$self->throw("There was not exactly 1 bam file and 1 bamcheck file per lane for lane $lane (@$files)") unless @$files == 2;
		
		my $basename = $lane;
		$basename =~ s/[^\w-]/_/g;
		my $output_file = $self->output_file(output_key => 'auto_qc_summary', basename => $basename.'.auto_qc.txt', type => 'txt');
		my $output_path = $output_file->path;
		
                my $cmd = "use VRPipe::Steps::vrtrack_auto_qc; VRPipe::Steps::vrtrack_auto_qc->auto_qc(db => q[$opts->{vrtrack_db}], bam => q[$files->[0]], bamcheck => q[$files->[1]], lane => q[$lane], auto_qc_gtype_regex => q[$opts->{auto_qc_gtype_regex}], auto_qc_mapped_base_percentage => $opts->{auto_qc_mapped_base_percentage}, auto_qc_duplicate_read_percentage => $opts->{auto_qc_duplicate_read_percentage}, auto_qc_mapped_reads_properly_paired_percentage => $opts->{auto_qc_mapped_reads_properly_paired_percentage}, auto_qc_error_rate => $opts->{auto_qc_error_rate}, auto_qc_insert_peak_window => $opts->{auto_qc_insert_peak_window}, auto_qc_insert_peak_reads => $opts->{auto_qc_insert_peak_reads}, auto_qc_max_ins_to_del_ratio => $opts->{auto_qc_max_ins_to_del_ratio}, results => q[$output_path]);";
                $self->dispatch_vrpipecode($cmd, $req, {output_files => [$output_file]});
            }
        };
    }
    method outputs_definition {
        return { auto_qc_summary => VRPipe::StepIODefinition->get(type => 'txt',
                                                                  description => 'a summary text file explaining why the auto qc passed or failed',
                                                                  max_files => -1) };
    }
    method description {
        return "Considering the stats in the bamcheck file for a lane, and the metadata stored on the bam file and in the VRTrack database for the corresponding lane, automatically decide if the lane passes the quality check.";
    }

    method auto_qc (ClassName|Object $self: Str :$db!, Str|File :$bam!, Str|File :$bamcheck!, Str|File :$results!, Str :$lane!, Str :$auto_qc_gtype_regex?, Num :$auto_qc_mapped_base_percentage?, Num :$auto_qc_duplicate_read_percentage?, Num :$auto_qc_mapped_reads_properly_paired_percentage?, Num :$auto_qc_error_rate?, Num :$auto_qc_insert_peak_window?, Num :$auto_qc_insert_peak_reads?, Num :$auto_qc_max_ins_to_del_ratio?) {
	my $bam_file = VRPipe::File->get(path => $bam);
	my $meta = $bam_file->metadata;
	my $bc = VRPipe::Parser->create('bamcheck', {file => $bamcheck});
	$bam_file->disconnect;
	
	# get the lane object from VRTrack
	my $vrtrack = $self->get_vrtrack(db => $db);
	my $vrlane = VRTrack::Lane->new_by_hierarchy_name($vrtrack, $lane) || $self->throw("No lane named '$lane' in database '$db'");
	my $mapstats = $vrlane->latest_mapping || $self->throw("There were no mapstats for lane $lane");
	
	my @qc_status = ();
	my ($test, $status, $reason);
	
	# check to see if the bam file contains any reads as this crashes other
	# parts of auto_qc 
	my $bam_has_seq = 1;
	if ($bc->sequences == 0 && $bc->total_length == 0) { # we use the bamcheck result, not $vrlane results, in case we're looking at unimproved exome bam which will have 0 reads and bases in VRTrack
	    $bam_has_seq = 0;
	    push @qc_status, { test => 'Empty bam file check', status => 0, reason => 'The bam file provided for this lane contains no sequences.' };
	}
	
	# we'll always fail if the npg status is failed
	my $npg_status = $vrlane->npg_qc_status;
	if ($npg_status && $npg_status eq 'fail') {
	    push @qc_status, { test => 'NPG QC status check', status => 0, reason => 'The lane failed the NPG QC check, so we auto-fail as well since this data will not be auto-submitted to EGA/ENA.' };
	}
	
	# genotype check results
	my @gtype_results;
	if (defined $auto_qc_gtype_regex) {
	    # use gtype info from bam_genotype_checking pipeline, if present
	    my $gstatus;
	    my $gtype_analysis = $meta->{gtype_analysis};
	    if ($gtype_analysis) {
		($gstatus) = $gtype_analysis =~ /status=(\S+) expected=(\S+) found=(\S+) ratio=(\S+)/;
		@gtype_results = ($gstatus, $2, $3, $4);
	    }
	    else {
		# look to see if there's a gtype status in VRTrack database for
		# this lane
		my $gt_found = $mapstats->genotype_found;
		if ($gt_found) {
		    my %lane_info = $vrtrack->lane_info($lane);
		    if ($gt_found eq $mapstats->genotype_expected || $gt_found eq $lane_info{sample} || $gt_found eq $lane_info{individual} || $gt_found eq $lane_info{individual_acc}) {
			$gstatus = 'confirmed';
		    }
		    else {
			$gstatus = 'wrong';
		    }
		}
	    }
	    
	    if ($gstatus) {
		$status = 1;
		$reason = qq[The status is '$gstatus'.];
		if ($gstatus !~ /$auto_qc_gtype_regex/) { 
		    $status = 0; 
		    $reason = "The status ($gstatus) does not match the regex ($auto_qc_gtype_regex)."; 
		}
		push @qc_status, { test => 'Genotype check', status => $status, reason => $reason };
	    }
	}
	
	# mapped bases
	if (defined $auto_qc_mapped_base_percentage && $bam_has_seq) {
	    my $min = $auto_qc_mapped_base_percentage;
	    $status = 1;
	    my $clip_bases = $mapstats->clip_bases;
	    my $bases_mapped_c = $mapstats->bases_mapped;
	    my $value = 100 * $bases_mapped_c / $clip_bases ;
	    $reason = sprintf "At least %.1f%% bases mapped after clipping (%.2f%%).", $min, $value;
	    if ($value < $min) {
		$status = 0;
		$reason = sprintf "Less than %.1f%% bases mapped after clipping (%.2f%%).", $min, $value;
	    }
	    push @qc_status, { test => 'Mapped bases', status => $status, reason => $reason };
	}
	
	# duplicate reads
	if (defined $auto_qc_duplicate_read_percentage && $bam_has_seq) {
	    my $max = $auto_qc_duplicate_read_percentage;
	    $status = 1;
	    my $mapped_reads = $mapstats->reads_mapped;
	    my $dup_reads = $mapped_reads - $mapstats->rmdup_reads_mapped;
	    my $value = 100 * $dup_reads / $mapped_reads;
	    $reason = sprintf "%.1f%% or fewer reads were duplicates (%.2f%%).", $max, $value;
	    if ($value > $max) {
		$status = 0;
		$reason = sprintf "More than %.1f%% reads were duplicates (%.2f%%).", $max, $value;
	    }
	    push @qc_status, { test => 'Duplicate reads', status => $status, reason => $reason };
	}
	
	# properly paired mapped reads
	if (defined $auto_qc_mapped_reads_properly_paired_percentage && $bam_has_seq) {
	    my $min = $auto_qc_mapped_reads_properly_paired_percentage;
	    $status = 1;
	    my $mapped_reads = $mapstats->reads_mapped;
	    my $paired_reads = $mapstats->rmdup_reads_mapped;
	    my $value = 100 * $paired_reads / $mapped_reads;
	    $reason = sprintf "%.1f%% or more reads that were mapped are in a proper pair (%.2f%%).", $min, $value;
	    if ($value < $min) {
		$status = 0;
		$reason = sprintf "Less than %.1f%% of reads that were mapped are in a proper pair (%.2f%%).", $min, $value;
	    }
	    push @qc_status, { test => 'Reads mapped in a proper pair', status => $status, reason => $reason };
	}
	
	# error rate
	if (defined $auto_qc_error_rate) {
	    my $max = $auto_qc_error_rate;
	    $status = 1;
	    my $error_rate = $mapstats->error_rate;
	    $reason = "The error rate is lower than $max ($error_rate).";
	    if ($error_rate > $max) {
		$status = 0;
		$reason = "The error rate is higher than $max ($error_rate).";
	    }
	    push @qc_status, { test => 'Error rate', status => $status, reason => $reason };
	}
	
	# number of insertions vs deletions 
	if (defined $auto_qc_max_ins_to_del_ratio) {
	    my $max = $auto_qc_max_ins_to_del_ratio;
	    $status = 1;
	    my ($inum, $dnum);
	    my $counts = $bc->indel_dist();
	    for my $row (@$counts) {
		$inum += $$row[1];
		$dnum += $$row[2];
	    }
	    $reason = "The Ins/Del ratio is smaller than $max ($inum/$dnum)";
	    if (! $dnum or $inum/$dnum > $max) {
		$status = 0;
		$reason = "The Ins/Del ratio is bigger than $max ($inum/$dnum)";
	    }
	    push @qc_status, { test => 'InDel ratio', status => $status, reason => $reason };
	}
	
	# insert size
	my $lib_to_update;
	my $lib_status;
	if ($vrlane->is_paired() && defined $auto_qc_insert_peak_window && defined $auto_qc_insert_peak_reads && $bam_has_seq) {
	    $test = 'Insert size';
	    
	    if ($mapstats->reads_paired == 0) {
		push @qc_status, { test => $test, status => 0, reason => 'Zero paired reads, yet flagged as paired' };
	    }
	    elsif ($mapstats->mean_insert == 0 || ! $bc->insert_size()) { 
		push @qc_status, { test => $test, status => 0, reason => 'The insert size not available, yet flagged as paired' };
	    }
	    else {
		# only libraries can be failed based on wrong insert size. The
		# lanes are always passed as long as the insert size is
		# consistent with other lanes from the same library.
		my $peak_win = $auto_qc_insert_peak_window;
		my $within_peak = $auto_qc_insert_peak_reads;
		
		$status = 1;
		my ($amount, $range) = $self->insert_size_allowed_amount_and_range($bc->insert_size(), $peak_win, $within_peak);
		
		$reason = sprintf "There are %.1f%% or more inserts within %.1f%% of max peak (%.2f%%).", $within_peak, $peak_win, $amount;
		if ($amount < $within_peak) { 
		    $status = 0;
		    $reason = sprintf "Fail library, less than %.1f%% of the inserts are within %.1f%% of max peak (%.2f%%).", $within_peak, $peak_win, $amount; 
		}
		push @qc_status, { test => $test, status => 1, reason => $reason };
		
		$reason = sprintf "%.1f%% of inserts are contained within %.1f%% of the max peak (%.2f%%).", $within_peak, $peak_win, $range;
		if ($range > $peak_win) {
		    $status = 0;
		    $reason = sprintf "Fail library, %.1f%% of inserts are not within %.1f%% of the max peak (%.2f%%).", $within_peak, $peak_win, $range;
		}
		push @qc_status, { test => 'Insert size (rev)', status => 1, reason => $reason };
		
		$lib_to_update = VRTrack::Library->new_by_field_value($vrtrack, 'library_id', $vrlane->library_id()) or $self->throw("No vrtrack library for lane $lane?");
		$lib_status = $status ? 'passed' : 'failed';
	    }
	}
	
	# now output the results
	my $results_file = VRPipe::File->get(path => $results);
	my $ofh = $results_file->openw;
	$status = 1;
	for my $stat (@qc_status) {
	    if (! $stat->{status}) {
		$status = 0;
	    }
	    print $ofh "$stat->{test}:\t", ($stat->{status} ? 'PASSED' : 'FAILED'), "\t # $stat->{reason}\n";
	}
	print $ofh "Verdict:\t", ($status ? 'PASSED' : 'FAILED'), "\n";
	$results_file->close;
	
	# write results to the VRTrack database
	my $worked = $vrtrack->transaction(sub {
	    if ($lib_to_update) {
		# don't pass the library if another lane has previously set it
		# to failed
		my $do_update = 1;
		my $current_status = $lib_to_update->auto_qc_status;
		if ($lib_status eq 'passed' && $current_status && $current_status eq 'failed') {
		    $do_update = 0;
		}
		
		if ($do_update) {
		    $lib_to_update->auto_qc_status($lib_status);
		    $lib_to_update->update();
		}
	    }
	    $vrlane->auto_qc_status($status ? 'passed' : 'failed');
	    
	    # also, if we did our own genotype check, write those results back
	    # to VRTrack now
	    if (@gtype_results) {
		my $mapstats = $vrlane->latest_mapping;
		$mapstats->genotype_expected($gtype_results[1]);
		$mapstats->genotype_found($gtype_results[2]);
		$mapstats->genotype_ratio($gtype_results[3]);
		$mapstats->update();
		
		$vrlane->genotype_status($gtype_results[0]);
	    }

	    # Add autoqc reasons to vrtrack
	    my @autoqc_statuses = @{ $lane->autoqcs() };
            if (@autoqc_statuses) {
		foreach my $autoqc (@autoqc_statuses) {
		    autoqc->current_run('0');
		    autoqc->update();
		}
	    }

	    foreach my $stat (@qc_status)
	    {
		my $autoqc_status = $vrlane->add_autoqc();
		$autoqc_status->test($$stat{test});
		$autoqc_status->result($$stat{status});
		$autoqc_status->reason($$stat{reason});
		$autoqc_status->update();
	    }
	    
	    $vrlane->update();
	});
	
	if ($worked) {
	    # also add the result as metadata on the bam file
	    $bam_file->add_metadata({auto_qc_status => $status ? 'passed' : 'failed'}, replace_data => 1);
	}
	else {
	    $self->throw($vrtrack->{transaction_error});
	}
    }
    
    # 1) what percentage of the data lies within the allowed range from the max
    #    peak (e.g. [mpeak*(1-0.25),mpeak*(1+0.25)])
    # 2) how wide is the distribution - how wide has to be the range to
    #    accomodate the given amount of data (e.g. 80% of the reads) 
    method insert_size_allowed_amount_and_range (ClassName|Object $self: ArrayRef $vals, Num $maxpeak_range, Num $data_amount) {
	# determine the max peak
	my $count = 0;
	my $imaxpeak = 0;
	my $ndata = scalar @$vals;
	my $total_count = 0;
	my $max = 0;
	for (my $i = 0; $i < $ndata; $i++) {
	    my $xval = $$vals[$i][0];
	    my $yval = $$vals[$i][1];
	    
	    $total_count += $yval;
	    if ($max < $yval) {
		$imaxpeak = $i;
		$max = $yval;
	    }
	}
	
	# see how many reads are within the max peak range
	$maxpeak_range *= 0.01;
	$count = 0;
	for (my $i = 0; $i < $ndata; $i++) {
	    my $xval = $$vals[$i][0];
	    my $yval = $$vals[$i][1];
	    
	    if ($xval < $$vals[$imaxpeak][0] * (1 - $maxpeak_range)) { next; }
	    if ($xval > $$vals[$imaxpeak][0] * (1 + $maxpeak_range)) { next; }
	    $count += $yval;
	}
	my $out_amount = 100 * $count / $total_count;
    
	# how big must be the range in order to accomodate the requested amount
	# of data
	$data_amount *= 0.01;
	my $idiff = 0;
	$count = $$vals[$imaxpeak][1];
	while ($count / $total_count < $data_amount) {
	    $idiff++;
	    if ($idiff <= $imaxpeak) { $count += $$vals[$imaxpeak-$idiff][1]; }
	    if ($idiff + $imaxpeak < $ndata) { $count += $$vals[$imaxpeak+$idiff][1]; }
	    
	    # this should never happen, unless $data_range is bigger than 100%
	    if ($idiff > $imaxpeak && $idiff + $imaxpeak>=$ndata ) { last; }
	}
	my $out_range  = $idiff <= $imaxpeak ? $$vals[$imaxpeak][0] - $$vals[$imaxpeak-$idiff][0] : $$vals[$imaxpeak][0];
	my $out_range2 = $idiff + $imaxpeak < $ndata ? $$vals[$imaxpeak + $idiff][0] - $$vals[$imaxpeak][0] : $$vals[-1][0] - $$vals[$imaxpeak][0];
	if ($out_range2 > $out_range) { $out_range = $out_range2; }
	$out_range = 100 * $out_range / $$vals[$imaxpeak][0];
	
	return ($out_amount, $out_range);
    }
}

1;
