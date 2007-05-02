#!/usr/bin/perl
###########
# maindb_nwconf.pl
#
# add the base config to networker
#
#
#
#####

###### 
# Do not remove or disable without good documented reason.
#
use strict;
use warnings;
# addtional 
use Getopt::Std;
#
######

######
# Variable processing
# 
# Make our variables global
# any new config variable belongs here
#
use vars qw($NSRSERVER $NSRADM $RTMP $DEBUG %options @CLUSTERNODES  
$TMPCMDFILE $TRUN $SID $BPOLICY $RPOLICY $POOLNAME $SAVEGROUP $NSRMM
$BACKPATH $BACKUP $CREATEPOOL $POOLRECYCLE $GROUPNAME $POOLGROUPS
$SCHEDULE $ECHO @preconfigured); 
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
$NSRSERVER="sdp_nsr";
#
# the names of the cluster nodes primary node first
@CLUSTERNODES=("sdp1","sdp2");
#
# The oracle DB You'll be backing up
$SID="test1";
#
# Group to configure
$GROUPNAME="mainDB-test1";
#
# set the default browse and retention policies.
# these get overridden anyway by the manual 
# backup policies so this dosen't matter.  Just set
# to the longest time any backup will be kept
$BPOLICY="Year";
$RPOLICY="Year";
#
# NetWorker Backup Schedule
$SCHEDULE="FullAlways";
#
$POOLNAME="MainDB-backup";
#
# all groups configured into a pool
# (can  be comma seperated list
$POOLGROUPS="mainDB-test1";
#
# allow recycling between pools
$POOLRECYCLE="yes";
#
# setup the temp dir we'll use
$RTMP="/nsr/tmp";
#
#
$BACKPATH="/nsr/savelists";
#
# 
$TMPCMDFILE="$RTMP/$SID";
#
#
$ECHO="/usr/bin/echo -e";

##### end variable default
#
# initialize some variables
$DEBUG=0;
$TRUN=0;

$BACKUP=0;
$CREATEPOOL=0;


#####
# set up our options
#
# -D: debug
# -t: test only, works very nice with -D
# -b: create backup config
# -p: create pools
# -c: config file
#
#
getopts('Dtbpc:',\%options);

####
# make command line switches do something
#
# just makes code easier to read, really.
if ($options{D}) { $DEBUG=1;}
if ($options{b}) { $BACKUP=1;}
if ($options{p}) { $CREATEPOOL=1;}
if ($options{t}) { $TRUN=1;}
#
# if nothing gets selected, select all types
if ((!$options{p}) && (!$options{b})) {
	$CREATEPOOL=1;
	$BACKUP=1;
}


##### read in config files
if ($options{c}) {
	if ( -e "$options{c}") { 
		print "reading $options{c}\n";
		no strict 'refs';
		open ( CONF, "$options{c}") || die "cannot open config: $!\n";
		my $conf = join "", <CONF>; 
		close CONF;
		eval $conf;
		die "Couldn't eval config file: $@\n" if $@;
		print "config file loaded\n";
	} else {print "Config file not found, using defaults\n";}
}
#####
#
# Set up the program locations we'll use
#
# nsradmin location
$NSRADM="nsradmin";
#
# nsrmm location
$NSRMM="nsrmm";
# 
####




print "Debug flag set\n" if $DEBUG;
print "Test Run flag set, no configuration will be performed\n" if $TRUN;
#
#
#####
#
#


sub resource_test {
	my $resourcetype="$_[0]";
	my $name="$_[1]";

	open(NWRTST, "$ECHO 'show name;\n\nprint NSR $resourcetype;\n' |$NSRADM -s $NSRSERVER -i - |") || die "can't open nsradmin: $!\n";
	my @nwresourcetest=<NWRTST>;
	print "@nwresourcetest\n\n" if $DEBUG;
	my @rlist;
	foreach (@nwresourcetest) {
		if(/\s+name: (.*);/) {
			#print "match: $1\n" if $DEBUG;
			push(@rlist, $1);
		}

	} # close output list
	close (NWRTST);
	my $exists;
	foreach (@rlist) {
		if (m/$name/) {
			$exists="1";
			}else{ 
			next;
		}
	}

	if ($exists) {
		print "networker $resourcetype $name found\n";
		return(1);
	}else{
		print "networker $resourcetype $name not found\n";
		return(0);
	}


}




sub create_backup_config {

	my @cl_admprivs;
	my $cl_admprivs_print;
	my $response="y";
	my @preconfigured;

	foreach my $cn (@CLUSTERNODES) { # Nota: cn = clusternode
		chomp($cn);
		print "configure $cn ...\n" if $DEBUG;
		my $createadm="host="."$cn";
		print "$createadm ...\n" if $DEBUG;
		push(@cl_admprivs, $createadm);
	}
	$cl_admprivs_print = join (",",@cl_admprivs);

	print "cluster hosts admin config:\n $cl_admprivs_print\n" if $DEBUG;

	if ($TRUN) { $response="n"; }

	# Create tempfile containing nsradmin commands
	open (NSRCMD, "> $TMPCMDFILE");
	#
	# print it to the file


	print NSRCMD  << "BACKUP";


create type: NSR group
name: $GROUPNAME;
comment:Main backup for $SID;
force incremental: No;
success threshold: Warning;

$response




create type: NSR client;
name: $NSRSERVER;
backup command: save -I $BACKPATH/$SID;
comment:$SID Backup;
group: $GROUPNAME;
remote access: $cl_admprivs_print;
retention policy: $RPOLICY;
browse policy: $BPOLICY;
save set: $BACKPATH/$SID;
schedule: FullAlways;

$response




BACKUP

	print NSRCMD "quit\n";
	close (NSRCMD);
	
	# call nsrdadmin and use the tempfile
	#
	print "running nsradmin\n";
	
	open (NSRADMIN, "$NSRADM  -i $TMPCMDFILE-b 2>&1|") || die "Cannot start nsradmin: $!\n";
	my @nsradm=<NSRADMIN>;
	close (NSRADMIN);
	print "nsradmin out:\n @nsradm \n\n" if $DEBUG;

	#
	#
	foreach my $nsradm_ln (@nsradm) {
		if ($nsradm_ln =~ m/.*failed.*already.exists.*/) {
			print "c";
			print "onfigured: $nsradm_ln\n" if $DEBUG;
			my @config_ln = split(":", $nsradm_ln);
			push (@preconfigured, $config_ln[1]);
		} if ($nsradm_ln =~ m/.*failed.*/) {
			print "$nsradm_ln\n";
			die "nsradm failed\n";
		}
	} 


	# remove the temp command file
	#
	if ((!$DEBUG) && (!$TRUN)) {
		unlink ($TMPCMDFILE.-b);
	}

}

sub update_backup_config {

	my @cl_admprivs;
	my $cl_admprivs_print;
	my $response="y";
	my @preconfigured;

	foreach my $cn (@CLUSTERNODES) { # Nota: cn = clusternode
		chomp($cn);
		print "configure $cn ...\n" if $DEBUG;
		my $createadm="host="."$cn";
		print "$createadm ...\n" if $DEBUG;
		push(@cl_admprivs, $createadm);
	}
	$cl_admprivs_print = join (",",@cl_admprivs);

	print "cluster hosts admin config:\n $cl_admprivs_print\n" if $DEBUG;

	if ($TRUN) { $response="n"; }

	# Create tempfile containing nsradmin commands
	open (NSRCMD, "> $TMPCMDFILE");
	#
	# print it to the file


	print NSRCMD  << "BACKUP";


create  type: NSR group 
name: $GROUPNAME;
comment:Main backup for $SID;
force incremental: No;
success threshold: Warning;

$response




print  type: NSR client; name: $NSRSERVER; save set: $BACKPATH/$SID

update group: $GROUPNAME;

$response


update backup command: save -I $BACKPATH/$SID;

$response


update remote access: $cl_admprivs_print;


$response


update retention policy: $RPOLICY;


$response


update browse policy: $BPOLICY;

$response


update save set: $BACKPATH/$SID;

$response


update schedule: $SCHEDULE;

$response




BACKUP

	print NSRCMD "quit\n";
	close (NSRCMD);
	
	# call nsrdadmin and use the tempfile
	#
	print "running nsradmin\n";
	
	open (NSRADMIN, "$NSRADM  -i $TMPCMDFILE-b 2>&1|") || die "Cannot start nsradmin: $!\n";
	my @nsradm=<NSRADMIN>;
	close (NSRADMIN);
	print "nsradmin out:\n @nsradm \n\n" if $DEBUG;

	#
	#
	foreach my $nsradm_ln (@nsradm) {
		if ($nsradm_ln =~ m/.*failed.*already.exists.*/) {
			print "c";
			print "onfigured: $nsradm_ln\n" if $DEBUG;
			my @config_ln = split(":", $nsradm_ln);
			push (@preconfigured, $config_ln[1]);
		} if ($nsradm_ln =~ m/.*failed.*/) {
			print "$nsradm_ln\n";
			die "nsradm failed\n";
		}
	} 


	# remove the temp command file
	#
	if ((!$DEBUG) && (!$TRUN)) {
		unlink ($TMPCMDFILE.-b);
	}

}




#####
#
#
sub create_pool_config {

	my $response="y";

	if ($TRUN) { $response="n"; }

	# Create tempfile containing nsradmin commands
	open (NSRCMD, "> $TMPCMDFILE-p");
	#
	# print it to the file


	print NSRCMD  << "POOL";




create type: type: NSR pool
name: $POOLNAME;
groups: $POOLGROUPS;
label template: Default;
pool type: Backup;
Recycle from other pools: No;
Recycle to other pools: No;
store index entries: Yes;

$response




POOL

	print NSRCMD "quit\n";
	close (NSRCMD);
	
	# call nsrdadmin and use the tempfile
	#
	print "running nsradmin\n";
	
	open (NSRADMIN, "$NSRADM  -i $TMPCMDFILE-p 2>&1|") || die "Cannot start nsradmin: $!\n";
	my @nsradm=<NSRADMIN>;
	close (NSRADMIN);
	print "nsradmin out:\n @nsradm \n\n" if $DEBUG;

	#
	#
	foreach my $nsradm_ln (@nsradm) {
		if ($nsradm_ln =~ m/.*failed.*already.exists.*/) {
			print "c";
			print "onfigured: $nsradm_ln\n" if $DEBUG;
			my @config_ln = split(":", $nsradm_ln);
			push (@preconfigured, $config_ln[1]);
		} if ($nsradm_ln =~ m/.*failed.*/) {
			print "$nsradm_ln\n";
			die "nsradm failed\n";
		}


	} 


	# remove the temp command file
	#
	if ((!$DEBUG) && (!$TRUN)) {
		unlink ($TMPCMDFILE.-p);
	}

}
#
#
#####


#####
#
#
sub update_pool_config {

	my $response="y";

	if ($TRUN) { $response="n"; }

	# Create tempfile containing nsradmin commands
	open (NSRCMD, "> $TMPCMDFILE-p");
	#
	# print it to the file


	print NSRCMD  << "POOL";




print type: type: NSR pool; name: $POOLNAME

update groups:$POOLGROUPS;

$response


update Recycle from other pools: $POOLRECYCLE;

$response


update Recycle to other pools: $POOLRECYCLE;

$response




POOL

	print NSRCMD "quit\n";
	close (NSRCMD);
	
	# call nsrdadmin and use the tempfile
	#
	print "running nsradmin\n";
	
	open (NSRADMIN, "$NSRADM  -i $TMPCMDFILE-p 2>&1|") || die "Cannot start nsradmin: $!\n";
	my @nsradm=<NSRADMIN>;
	close (NSRADMIN);
	print "nsradmin out:\n @nsradm \n\n" if $DEBUG;

	#
	#
	foreach my $nsradm_ln (@nsradm) {
		if ($nsradm_ln =~ m/.*failed.*already.exists.*/) {
			print "c";
			print "onfigured: $nsradm_ln\n" if $DEBUG;
			my @config_ln = split(":", $nsradm_ln);
			push (@preconfigured, $config_ln[1]);
		} if ($nsradm_ln =~ m/.*failed.*/) {
			print "$nsradm_ln\n";
			die "nsradm failed\n";
		}


	} 


	# remove the temp command file
	#
	if ((!$DEBUG) && (!$TRUN)) {
		unlink ($TMPCMDFILE.-p);
	}

}
#
#
#####

if ($BACKUP) {
	if (resource_test("group", $GROUPNAME)) {
		update_backup_config();
	} else {
		create_backup_config();
	}
}


if ($CREATEPOOL) {
	if (resource_test("pool",$POOLNAME)) {
		create_pool_config();
	} else {
		update_pool_config();
	}
}
