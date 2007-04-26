#!/usr/bin/perl
###########
# Source DB Backup procedure
# Oracle dump – process exists 
# Oracle validation – process exists 
# Available media check – check mminfo for (at least) 2 complete full savesets 
# if available media – permit backup 
# if no available media recycle media 
# *and* there is at least 1 (2?) valid backup if not send SNMP trap 
# Run backup of Oracle dump files – report success or failure 
# if failure – recycle media and send SNMP trap 
# Media validation test – restore files to test and log 
# if fail – recycle media and send SNMP trap 

#####

###### 
# Do not remove or disable without good documented reason.
#
use strict;
use warnings;
# addtional 
use Data::Dumper;
use Getopt::Std;
#
######

######
# Variable processing
# 
# Make our variables global
# any new config variable belongs here
#
use vars qw($NSRSERVER $NSRJB $MMINFO $SAVEGRPCMD $SVGRP_ROOT $SVGRP $NWSCH
	$FSSSN $BUINLST $MAXBACKUPS $BKUPFRQ $SSFN $backupset $DEBUG
	$NSRMM $opt_D %options $SYSTIME); 
#
######

#####
# set the defaults here and copy block to
# "/usr/ngscore/config/'progname'.conf" file
# 
## ## start config block ##
# 
#
#
# the Name of the clustered
# NetWorker server
$NSRSERVER="stinkpad-ii";
#
# root of savegroup for main db backups
$SVGRP_ROOT="main_db";
# 
# Saveset file name
$SSFN="bu_list.txt";
# fileset location/saveset name
$FSSSN="c:\\$SSFN";
#
# backup in list
$BUINLST="c:\\bu_list-in.txt";
#
# NW Backup Schedule
$NWSCH="FullAlways";
#
# number of backups to keep
$MAXBACKUPS=3;
#
# allowable backup time differental from last backup 
# in seconds (e.g. 3660 = 1hr, 43920 = 12 hr, 87840 = 1 day)
$BKUPFRQ=3660;
#
# nsrjb location
$NSRJB="nsrjb";
#
# nsrmm location
$NSRMM="nsrmm";
# 
# mminfo location
$MMINFO="mminfo -s $NSRSERVER -v -q volume=mainDB.001";
# 
# savegrp (save group) command
$SAVEGRPCMD="savegrp";
##### end variable default

#$backupset="test1";



#$SVGRP="$SVGRP_ROOT-$backupset";
$SVGRP="$SVGRP_ROOT-test1";

$DEBUG=0;

$SYSTIME=time();

#####
# set up our vars
#
getopts('fD',\%options);
#
#
# just makes code easier to read
$DEBUG=1 if $options{'D'};

# force backup by setting backup limit to 0
if ($options{'f'}) {
	print "forcing backup with -f flag\n";
	$BKUPFRQ=0;
}

print "Debug set\n" if $DEBUG;

# 

sub recycler {
	#
	# nsrmm - manupulates networker media db
	# -d deletes media index record associated with a saveset or volume
	# -v verbose
	# -y "yes", approves any action
	# -S specifies the ssid or ssid\cloneid pair
	open (RCYC, "$NSRMM -s $NSRSERVER -dvy -S $_[0] 2>&1|") || die "recycling $_[0] failed\n";
	my @re_in = <RCYC>;
	foreach my $re_ln (@re_in) {
		if ($re_ln =~ m/.*not.in.the.media.index.*/) {
			print "SSID $_[0] not in media index. already deleted?";
		} if ($re_ln =~ m/.*unknown.host.*/) {
			die "$NSRSERVER not found or unroutable\n";
		} else {
			print "SaveSet $_[0] removed\n";
			next;}

	}
}
	

#####
#
#
# Available media check – check mminfo for (at least) 2 complete full 
# savesets 
#
sub media_ck {
	#
	#
	print "performing saveset and media check\n";
	my $query="-q \"!incomplete\"";
	#my $query="-q name=\"$FSSSN\"";
	my $report="-r ssid,cloneid,name,nsavetime,savetime,volume,sumsize";
	open (SSIN, "$MMINFO -xc, $query $report 2>&1|") || die "$MMINFO failed: $!"; 
	my @ss_in = <SSIN>;
	my @ss_mid;
	my %ss_out;
	my @bu_sizes; # for creating a backup average
	my $bu_ave; # for estimating usage
	my @bu_mfd; # record SSIDs marked for deletion
	print "mminfo output:\n@ss_in\n" if $DEBUG;
	foreach my $ss_ln (@ss_in) {
		chomp($ss_ln);
		if ($ss_ln =~ m/.*$SSFN.*/) { #temp sorting of mminfo
			print "$ss_ln\n" if $DEBUG;
			my ($ssid, $clnid, $name, $nsavetime, 
				$savetime, $volume, $sumsize
			) =  split(',', $ss_ln);
			$sumsize =~ s/\ KB/000/;
			$sumsize =~ s/\ MB/000000/;
			$sumsize =~ s/\ GB/000000000/;
			print "backup size: $sumsize\n" if $DEBUG;

			if (($SYSTIME - $BKUPFRQ) < $nsavetime) {
				print "systime: $SYSTIME\nBackup Limit:$BKUPFRQ\nsavetime: $nsavetime\n";
				print "backup within time limit, wait to run or force with -f\n";
				exit;
			}
			push(@{$ss_out{$nsavetime}},
				$ssid."/".$clnid,
				$name,
				$savetime,
				$volume,
				$sumsize
			);

		} #temp sorting of mminfo
	}
	#print Dumper (%ss_out) if $DEBUG;
	my $bu_count=0;
	foreach my $k (reverse sort keys %ss_out) {
		print "r";
		++ $bu_count;
		my @ss_ref = @{$ss_out{$k}};
		#print "\n\nStuff: @{$ss_out{$k}}\n\n";
		my ($ssid, $name, $nsavetime, 
			$savetime, $volume, $sumsize
		) =  @{$ss_out{$k}};
		print "- backup $name from $k being processed \n" if $DEBUG;
		if ($MAXBACKUPS <= $bu_count) {
			print "o";
			print "- SSID $ssid queued for removal\n" if $DEBUG;
			push (@bu_mfd, $ssid);
		}
		#print Dumper ($ss_out{$k}) if $DEBUG;
		#print Dumper (@ss_ref) if $DEBUG;
		#print "savetime: $k\n stuff:@ss_ref\n";
		print "$bu_count";
	}
	print "\n\n";	
	foreach my $ssd (@bu_mfd) {
		print "recycling SaveSet: $ssd\n";
		recycler($ssd); ## take out the cans and bottles
	

	}
	


}
# if available media – permit backup 
# if no available media recycle media 
# *and* there is at least 1 (2?) valid backup if not send SNMP trap 
# or error
#
#####



#####
#
# Run backup of Oracle dump files – report success or failure 
#
# read in full file list
sub backup_list {
	print "creating filelist for $FSSSN\n";
	open (BU_INFILE, "$BUINLST") || die "Error reading $BUINLST, stopped: $!\n";
	my @backupset_in = <BU_INFILE>;
	
	my @backupset_out; # put the files here
	my @fnf; # missing files for backup report
	foreach my $bkupfile (@backupset_in) { 
		# test existance
		#if ( -e chomp($bkupfile) ) {
		if ( chomp($bkupfile) ) {

			# save the existing files to an array
			push (@backupset_out, $bkupfile);
		} else {
			# save off missing files to array for later reporting
			push (@fnf, $bkupfile);
		} ## close file test loop
	} ## end sort loop
	# TODO
	# create test file w/ timestamp & filelist
	# for now add the backup file to the list
	push (@backupset_out, $BUINLST);
	#
	# write the actual backup list
	open (BU_OUTFILE, "> $FSSSN") || die "Error writing $FSSSN, stopped: $!\n";
	
	foreach my $bkupfileout (@backupset_out){
		print BU_OUTFILE "$bkupfileout\n";
	}
	# 
	# TODO
	# this array could go somewhere either log or email or both
	if (@fnf) { print "these files not found:\n @fnf\n";}
	print "file: $FSSSN created\n";
} # end backup sub
#
# Start the group and dump to a filehandle
sub savegrp {
	print "starting backup to tape\n";

	open (SAVEGRP, "$SAVEGRPCMD -v -C $NWSCH -G $SVGRP 2>&1|" ) || die "$SAVEGRPCMD failed: $!";

	my @svgrp_in = <SAVEGRP>;
	my @svgrp_succeed;
	my @svgrp_fail;
	my @svgrp_slist;

	print "$SAVEGRPCMD output:\n @svgrp_in\n\n" if $DEBUG;

	foreach my $svg_ln (@svgrp_in) {
		#
		chomp ($svg_ln);
		# find the lines that show success
		if ( $svg_ln =~ m/.*succeed.*/) {
			print "s";
			push (@svgrp_succeed, $svg_ln);
		} if ($svg_ln =~ m/.*level.*files/) {
			print"$svg_ln\n";
		} if ($svg_ln =~ m/.*fail.*/) {
			push (@svgrp_fail, $svg_ln)
		} if ($svg_ln =~ m/.*$SSFN.*/) {
			$svg_ln =~ s/.*\://;
			push (@svgrp_slist, $svg_ln);
		} else { next; #print "uncaught line: $svg_ln\n"
		}
	} ## close svgrp result loop

	print "success report:\n\n @svgrp_succeed\n";

	print "failure report:\n @svgrp_fail\n" if @svgrp_fail ;

	print "NetWorker Backup File List:\n\n @svgrp_slist\n" if @svgrp_slist ;
}



#######
# main section of program
#


media_ck();
#backup_list();
savegrp();

# 
#
# if failure – recycle SSID and send SNMP trap 
# 
#
#
#
# Media validation test – restore files to test and log 
# if fail – recycle media and send SNMP trap 




