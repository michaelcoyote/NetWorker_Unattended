#!/usr/bin/perl
###########
# base_nwconf.pl
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
use vars qw($NSRSERVER $NSRADM $NSRJB $RTMP $DEBUG %options
@CLUSTERNODES $SNMPCOM $NSRTRAP $TMPCMDFILE $NSRMM $NSRTT
$NOTIFICATION $USERGROUP $SCHEDULES $TRUN); 
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
# 
$SNMPCOM="public";
#
# trap program
$NSRTRAP="/usr/bin/nsrtrap";
#
# NSR Trap Type
$NSRTT="6";
#
# setup the temp dir we'll use
$RTMP="/nsr/tmp";
#
$TMPCMDFILE="$RTMP/nsradmin-in";
#
##### end variable default
#
# initialize some variables
$DEBUG=0;

$NOTIFICATION=0;
$USERGROUP=0;
$SCHEDULES=0;
$TRUN=0;


#####
# set up our options
#
# -D: debug
# -n: create notifications
# -s: create schedules
# -u: update usergroups
# -c: config file
# -t: test only, works very nice with -D
#
#
getopts('Dtnsuc:',\%options);

####
# make command line switches do something
#
# just makes code easier to read, really.
if ($options{D}) { $DEBUG=1;}
if ($options{s}) { $SCHEDULES=1;}
if ($options{u}) { $USERGROUP=1;}
if ($options{n}) { $NOTIFICATION=1;}
if ($options{t}) { $TRUN=1;}
#
# if nothing gets selected, select all types
if ((!$SCHEDULES) && (!$USERGROUP) && (!$NOTIFICATION)) {
	$NOTIFICATION=1;
	$USERGROUP=1;
	$SCHEDULES=1;
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
$NSRJB="nsradmin";
# 
# nsradmin
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
sub update_stock_config {

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
	# print it to the file$NSRTT
	print NSRCMD  << "NOTIFICATION" if $NOTIFICATION;

create type: NSR notification; 
name: Resource File Corruption Trap;
event: Resource File;
priority: critical;
action: "$NSRTRAP -c $SNMPCOM -t $NSRTT $NSRSERVER";

$response


create type: NSR notification; 
name: Bootstrap Backup Failure Trap;
event: Bootstrap;
priority: alert;
action: "$NSRTRAP -c $SNMPCOM -t $NSRTT $NSRSERVER";

$response


create type: NSR notification; 
name: Bootstrap Trap;
event: Savegroup;
priority: critical;
action: "$NSRTRAP -c $SNMPCOM -t $NSRTT $NSRSERVER";

$response


create type: NSR notification;
name: Savegroup Completion Trap;
event: Savegroup;
priority: alert, notice;
action: "$NSRTRAP -c $SNMPCOM -t $NSRTT $NSRSERVER";

$response


NOTIFICATION

	print NSRCMD  << "USERGROUP" if $USERGROUP ;

update type: NSR usergroup; name: Administrators
users: "host=$NSRSERVER,$cl_admprivs_print";

$response


USERGROUP

	print NSRCMD  << "SCHEDULES" if $SCHEDULES;

create type: NSR schedule;
action: full full full full full full full;
comment:Comverse full always schedule;
name: FullAlways;
period: Week;

$response


SCHEDULES


	print NSRCMD "quit\n";
	close (NSRCMD);
	
	# call nsrdadmin and use the tempfile
	#
	print "running nsradmin\n";
	
	open (NSRADMIN, "$NSRADM  -i $TMPCMDFILE 2>&1|") || die "Cannot start nsradmin: $!\n";
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
	#unlink ($TMPCMDFILE);

}




update_stock_config();

