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
use vars qw($NSRSERVER $NSRJB $MMINFO $SAVEGRPCMD $GROUPNAME $LOGFILE $LOGLOC
	$SCHEDULE $FSSSN $BUINLST $MAXBACKUPS $BKUPFRQ $SSFILENAME $DEBUG
	$NSRMM $opt_D %options $SYSTIME $NOCHECK $NOLIST $NOBKUP $SID
	$RECOVER $RTMP $BUCKSUM $CHECKSUM $BACKPATH $NORECOVERTEST
	$LOGRETAIN $ORACLESTATUS $NOSTATCK); 
#
######

#####
# set the defaults here and copy block to your conf file
# 
## ## start config block ##
#
# the Name of the clustered
# NetWorker server
$NSRSERVER="sdp_nsr";
#
# Backups Path
$BACKPATH="/backup_vol";
#
# Oracle backup status file
$ORACLESTATUS="/backup_vol/status";
#
# Saveset file name
# this should be set to an oracle sid or 
# some other useful designation 
$SSFILENAME="bu_list";
#
# fileset location/saveset name
$FSSSN="/backup_vol/$SSFILENAME";
# 
# SaveGroup name
$GROUPNAME="main_db-test1";
# 
# backup in list
$BUINLST="/backup_vol/test1_backuplist";
# 
# NW Backup Schedule
$SCHEDULE="FullAlways";
#
# number of backups to keep
$MAXBACKUPS=3;
#
# allowable backup time differental from last backup 
# in seconds (e.g. 3660 = 1hr, 43920 = 12 hr, 87840 = 1 day)
$BKUPFRQ=3660;
#
# What is our log location
$LOGLOC="/var/tmp";
#
# Remove logs over n days old
# set to 0 to skip removal
$LOGRETAIN="10";
#
#
$RTMP="/nsr/tmp/";
#
# for skipping parts of the backup script.. for testing use only
$NOSTATCK=0;
$NOCHECK=0;
$NOLIST=0;
$NOBKUP=0;
$NORECOVERTEST=0;
#
##### end variable default
#
# set up some variables
$DEBUG=0;

$CHECKSUM=0;
#
# set it up once and operate on it 
# to avoid race condtions mostly
$SYSTIME=time();



#####
# set up our vars
#
# -f: force a backup
# -D: debug
# -c: config file
#
#
getopts('fDc:',\%options);
#
#

##### read in config files
if ($options{c}) {
	if ( -e "$options{c}") { 
		print "reading $options{c}\n";
		no strict 'refs';
		open ( CONF, "$options{c}") || die ("cannot open config: $!\n");
		my $conf = join "", <CONF>; 
		close CONF;
		eval $conf;
		die"Couldn't eval config file: $@\n" if $@;
		print "config file loaded\n";
	} else {print "Config file not found, using defaults\n";}
}
#####
# nsrjb location
$NSRJB="nsrjb";
#
# nsrmm location
$NSRMM="nsrmm";
# 
# mminfo location
$MMINFO="mminfo -s $NSRSERVER -v";
# 
# savegrp (save group) command
$SAVEGRPCMD="savegrp";
#
# networker recover
$RECOVER="recover";
####


####
# set up command line switches
#
# just makes code easier to read
$DEBUG=1 if $options{'D'};
#
# force backup by setting backup limit to 0
if ($options{'f'}) {
	print "forcing backup with -f flag\n";
	$BKUPFRQ=0;
}
#####
#
#
# Log function courtesy of Laramee Gerard <Gerard.Laramee@comverse.com>
#
$LOGFILE="$LOGLOC/mainbackup$$.log";

print "using $LOGFILE as the logfile\n";
# Log function you might find at your local Wal-Mart
sub Log {
	my %args = (
		'sub'            => '',
		'message'        => '',
		'level'          => 'INFO',
                @_,
	);
	my $date=`/usr/bin/date`;
	my $use_stdout=0;
	$use_stdout=1 unless(open(FILE, ">>$LOGFILE"));

	chomp($date);
	if ( $use_stdout ) {
		printf("%s %s: %s\n",$date,$args{level},$args{message}) if ($args{sub} eq '');
		printf("%s [%s] --> %s: %s\n",$date,$args{sub},$args{level},$args{message}) if ($args{sub} ne '');
	}
	else {
		printf(FILE "%s %s: %s\n",$date,$args{level},$args{message}) if ($args{sub} eq '');
		printf(FILE "%s [%s] --> %s: %s\n",$date,$args{sub},$args{level},$args{message}) if ($args{sub} ne '');
		close(FILE);

	}
}
sub Die {
 
	my ($status,$error) = @_;
	
	$ENV{ERROR} = $error if defined $error;
	$ENV{STATUS} = $status if defined $status;
 
	Exit ();
 
}

sub Exit {
	my ($status,$info) = @_;
 
	$ENV{STATUS} = $status if defined $status;
	$ENV{INFO} = $info if defined $info;
	$ENV{STATUS} = -1 unless exists $ENV{STATUS};
 
	print "STATUS=$ENV{STATUS}\n" if exists $ENV{STATUS};
	print "INFO=$ENV{INFO}\n" if exists $ENV{INFO} and $ENV{INFO};
	print "ERROR=$ENV{ERROR}\n" if exists $ENV{ERROR} and $ENV{ERROR};
	exit $ENV{STATUS};
}
###
#
# a quick function to log and die a process on error
sub DieNoisy {
	my ($sub,$status,$error) = @_;
	
	Log(sub => "$sub",
		message => "$error", 
		level => 'ERROR');
	
	$ENV{ERROR} = $error if defined $error;
	$ENV{STATUS} = $status if defined $status;
 
	Exit ();
 
}
#
###

###
#
sub logremove {
	my @findout = `find $LOGLOC -type f -name mainbackup*.log -mtime +$LOGRETAIN`;

	if (@findout) {

		foreach my $file (@findout) {
        		print ("removing $file\n");
			Log(sub => "logremove", message => "removing $file");
        		unlink ($file);
		}
	} else {
		Log(sub => "logremove", message => "no logfiles to remove");
	}

}
#
###

####
Log(message => 'Backup Starting');

print "Debug set\n" if $DEBUG;
Log(message => 'Debug set', level => 'DEBUG') if $DEBUG;

##### 
#
#
sub status_ck { 
	Log(sub => "status_ck", message => "checking oracle backup status file: $_[0]"); 
	print "checking oracle backup status file: $_[0]\n"; 
	open(STATUSFILE, "$_[0]") || DieNoisy('status_ck',1,"problem reading status file $_[0]: $!"); 
	my @statusck = <STATUSFILE>; 
	foreach my $status_ln (@statusck) { 
		if($status_ln =~ s/STATUS\=//) { 
			chomp($status_ln);
			print "oracle backup exit status: $status_ln\n"
			;Log(sub => "status_ck", message => "oracle backup exit status: $status_ln");
			if ($status_ln) { 
				print "oracle backup OK\n"; 
				Log(sub => "status_ck", message => "oracle backup OK"); 
			} else { 
				print "oracle backup check failed\n"; 
				DieNoisy('status_ck',1,"oracle backup check failed"); 
			}
		} 
	} 
} 

#
#
#####

#####
#
#

sub recycler {
	#
	# nsrmm - manupulates networker media db
	# -d deletes media index record associated with a saveset or volume
	# -v verbose
	# -y "yes", approves any action
	# -S specifies the ssid or ssid\cloneid pair
	open (RCYC, "$NSRMM -s $NSRSERVER -dvy -S $_[0] 2>&1|") || DieNoisy ('recycler',1,"recycling $_[0] failed");
	my @re_in = <RCYC>;
	foreach my $re_ln (@re_in) {
		if ($re_ln =~ m/.*not.in.the.media.index.*/) {
			Log(sub => 'recycler', message => "SSID $_[0] not in media index. already deleted?", level => 'WARNING');
			print "SSID $_[0] not in media index. already deleted?\n";
		} if ($re_ln =~ m/.*unknown.host.*/) {
			Log(sub => 'recycler', message => "$NSRSERVER not found or unroutable",level => 'ERROR');
			Die(1,"$NSRSERVER not found or unroutable");
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
	#my $query="-q \"!incomplete\"";
	my $query="-q name=\"$FSSSN\" -q \"!incomplete\"";
	my $report="-r ssid,cloneid,name,nsavetime,savetime,volume,sumsize,client";
	open (SSIN, "$MMINFO -xc, $query $report 2>&1|") || DieNoisy('media_ck',1,"$MMINFO failed: $!"); 
	my @ss_in = <SSIN>;
	my @ss_mid;
	my %ss_out;
	my @bu_sizes; # for creating a backup average
	my $bu_ave; # for estimating usage
	my @bu_mfd; # record SSIDs marked for deletion
	print "mminfo output:\n@ss_in\n" if $DEBUG;
	Log(sub => 'media_ck', message => "mminfo output:\n@ss_in",level => 'DEBUG') if $DEBUG;
	foreach my $ss_ln (@ss_in) {
		chomp($ss_ln);
		if ($ss_ln =~ m/.*$SSFILENAME.*/) { #temp sorting of mminfo
			print "$ss_ln\n" if $DEBUG;
			Log(sub => 'media_ck', message => "$ss_ln",level => 'DEBUG') if $DEBUG;
			my ($ssid, $clnid, $name, $nsavetime, 
				$savetime, $volume, $sumsize,$client
			) =  split(',', $ss_ln);
			$sumsize =~ s/\ KB/000/;
			$sumsize =~ s/\ MB/000000/;
			$sumsize =~ s/\ GB/000000000/;
			print "backup size: $sumsize\n" if $DEBUG;
			Log(sub => 'media_ck', message => "backup size: $sumsize",level => 'DEBUG') if $DEBUG;

			if (($SYSTIME - $BKUPFRQ) < $nsavetime) {  
				Log(level => 'WARNING',sub => 'media_ck', message => "systime: $SYSTIME\nBackup Limit:$BKUPFRQ\nsavetime: $nsavetime, backup within time limit, wait to run or force with -f");
				print "systime: $SYSTIME\nBackup Limit:$BKUPFRQ\nsavetime: $nsavetime\n";
				print "backup within time limit, wait to run or force with -f\n";
				# TODO: set exit status to warning
				# i.e $ENV{STATUS} = $WARNING; 
				$ENV{INFO} = "systime: $SYSTIME  Backup Limit:$BKUPFRQ  savetime: $nsavetime, backup within time limit, wait to run or force with -f";
				Exit;
			}
			push(@{$ss_out{$nsavetime}},
				$ssid."/".$clnid,
				$name,
				$savetime,
				$volume,
				$sumsize,
				$client
			);

		} #temp sorting of mminfo
	}
	print Dumper (%ss_out) if $DEBUG;
	my $bu_count=0;
	foreach my $k (reverse sort keys %ss_out) {
		print "r";
		++ $bu_count;
		my @ss_ref = @{$ss_out{$k}};
		my ($ssid, $name, $nsavetime, $savetime, 
			$volume, $sumsize, $client
		) =  @{$ss_out{$k}};
		print "- backup $name from $k being processed \n" if $DEBUG;
		Log(sub => 'media_ck', message => "backup $name from $k being processed",level => 'DEBUG') if $DEBUG;
		if ($MAXBACKUPS <= $bu_count) {
			print "o";
			print "- SSID $ssid queued for removal\n" if $DEBUG;
			Log(sub => 'media_ck', message => "SSID $ssid queued for removal",level => 'DEBUG') if $DEBUG;
			push (@bu_mfd, $ssid);
		}
		print "$bu_count";
	}
	print "\n\n";	
	foreach my $ssd (@bu_mfd) {
		print "recycling SaveSet: $ssd\n";
		Log(sub => 'media_ck', message => "recycling SaveSet: $ssd");
		recycler($ssd); ## take out the cans and bottles

	}
	
}
# if available media – permit backup 
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
	Log(sub => 'backup_list', message => "creating filelist for $FSSSN");
	open (BU_INFILE, "$BUINLST") || DieNoisy('backup_list',1, "Error reading $BUINLST, stopped: $!");
	my @backupset_in = <BU_INFILE>;
	my @backupset_out; # put the files here
	my @backupck_out; # put the files here
	my @fnf; # missing files for backup report
	foreach my $bkupfile (@backupset_in) { 
		chomp($bkupfile);
		# test existance
		if ( -e $bkupfile) {
			#
			# save the existing files to an array
			push (@backupset_out, $bkupfile);
		} else {
			# save off missing files to array for later reporting
			push (@fnf, $bkupfile);
		} ## close file test loop
	} ## end sort loop
	#
	# no point in backing up an empty file.
	# error out and let people know
	if (!@backupset_out) {
		DieNoisy('backup_list',1,"backup file set empty");
	}
	# for now add the backup files to the list
	push (@backupset_out,$BUINLST);
	push (@backupset_out,$FSSSN);
	#
	# write the actual backup list
	open (BU_OUTFILE, "> $FSSSN") || DieNoisy ('backup_list',1,"Error writing $FSSSN, stopped: $!\n");
	
	foreach my $bkupfileout (@backupset_out){
		print "$bkupfileout\n" if $DEBUG;
		print BU_OUTFILE "$bkupfileout\n";
	}
	# 
	# TODO
	# this array could go somewhere either log or email or both
	if (@fnf) { print "these files not found:\n ";
		Log(sub => 'backup_list', message => "these files not found:",level => 'WARNING');
		foreach my $f (@fnf){
		Log(sub => 'backup_list', message => "$f",level => 'WARNING');
		print "$f\n"}
	}
	print "file: $FSSSN created\n";
} # end listmaking  sub
#
# Start the group and dump to a filehandle
sub savegrp {
	print "starting backup to tape\n";

	open (SAVEGRP, "$SAVEGRPCMD -v -C $SCHEDULE -G $GROUPNAME 2>&1|" ) || DieNoisy('savegrp',1, "$SAVEGRPCMD failed: $!");

	my @svgrp_in = <SAVEGRP>;
	my @svgrp_succeed;
	my @svgrp_fail;
	my @svgrp_slist;

	print "$SAVEGRPCMD output:\n @svgrp_in\n\n" if $DEBUG;

	foreach my $svg_ln (@svgrp_in) {
		#
		#chomp ($svg_ln);
		# find the lines that show success
		if ( $svg_ln =~ m/.*succeed.*/) {
			print "s";
			push (@svgrp_succeed, $svg_ln);
		} if ($svg_ln =~ m/.*level.*files/) {
			print"$svg_ln\n";
		} if ($svg_ln =~ m/.*fail.*/) {
			push (@svgrp_fail, $svg_ln)
		} if ($svg_ln =~ m/.*no.group.named.*/) {
			push (@svgrp_fail, $svg_ln)
		} if ($svg_ln =~ m/.*$SSFILENAME.*/) {
			$svg_ln =~ s/.*\://;
			push (@svgrp_slist, $svg_ln);
		} else { next; #print "uncaught line: $svg_ln\n"
		}
	} ## close svgrp result loop

	print "success report:\n\n @svgrp_succeed\n";

	if (@svgrp_fail) {
		print "failure report:\n @svgrp_fail\n" if @svgrp_fail ; 
		DieNoisy('savegrp',1,"failure report:\n @svgrp_fail");
	}	

	print "NetWorker Backup File List:\n\n @svgrp_slist\n" if @svgrp_slist ;
}
#
#
#####

#####
# recover()
# takes in full pathname and
# returns the path to the recovered file
#

sub recover {
	print "recovering $_[0]\n";
	Log(sub => 'recover', message => "recovering $_[0]");
        open (RTEST, "$RECOVER -s $NSRSERVER -f -d $RTMP -a $_[0]  2>&1|") || DieNoisy('recover',1,"Recovery failed: $!");
        my @recovtest = <RTEST>;
	print "DEBUG recover output\n @recovtest \n" if $DEBUG;
	Log(sub => 'recover', message => "DEBUG recover output\n @recovtest",level => 'DEBUG');
        my $r_file;
        foreach my $r_ln (@recovtest) {
                chomp($r_ln);
                if ($r_ln =~ m/^Received.1.file.*/) {
                        print "recovery successful\n"; 
			Log(sub => 'recover',message => 'recovery successful');
                        return($r_file);
                } if ($r_ln =~ m/^Nothing.to.recover.*/) {
                        print "recovery failed\n";
			DieNoisy('recover',1,"problem with recovery, file not found. recover output:\n @recovtest");
                        return($r_file);
                } else {next;}
                print "problem with recovery\n";
		print "recover output:\n @recovtest\n";
		DieNoisy('recover',1,"problem with recovery, recover output:\n @recovtest");

        }
}
#
#
#####

#####
# checksum()
# takes in a file and returns a
# old bsd style checksum
#
sub checksum {
        #create a SysV style checksum
        # same as "sum -o file" on AIX
	print "entering checksum subroutine\n";
	Log(sub => 'checksum', message => "entering checksum subroutine");
        my $sum=0;
        open (CKFILE, "$_[0]") || DieNoisy('checksum',1,"cant open file for checksumming $_[0]\n");
	print "creating checksum for $_[0]\n";
        while (<CKFILE>){
                $sum += unpack("%16C*",$_);}
        $sum %= (2 ** 16) - 1;
        close (CKFILE);
        return ($sum);
}
#
#
#####

#####
# filetest()
# restores a file compares with its
# original via a checksum
#
sub filetest {
        use File::Basename;
        recover($_[0]);
        my $rfile = basename($_[0]);
	my $ofilesum = checksum($_[0]);
	print "checksum for $_[0]: $ofilesum\n";
	Log(sub => 'filetest', message => "checksum for $_[0]: $ofilesum");
	my $rfilesum = checksum("$RTMP/$rfile");
	print "checksum for $RTMP/$rfile: $rfilesum\n";
	Log(sub => 'filetest', message => "checksum for $RTMP/$rfile: $rfilesum");

        if (($ofilesum)&&($rfilesum)&&($ofilesum eq $rfilesum )) {
                print "restore checksum passed\n";
		Log(sub => 'filetest', message => "restore checksum passed");
                return(0);
        } else {
                print "restore checksum failed\n";
		Log(sub => 'filetest', message => "restore checksum failed", level => 'ERROR');
                return(1);
        }
} ## end filetest sub
#
#
#####

#######
# main section of program
#

# 
# 
status_ck($ORACLESTATUS) if (!$NOSTATCK);
#
# if $LOGRETAIN is nonzero run the subroutine
logremove() if ($LOGRETAIN);
#
# media check for savesets
media_ck() if (!$NOCHECK);
#
# create the backuplist that will be used as the saveset
backup_list() if (!$NOLIST);
# 
# start the actual save
savegrp() if (!$NOBKUP);
# 
# do a recovery test on the recovered $BUINLIST
filetest($BUINLST) if (!$NORECOVERTEST);

#
# end
#### 
