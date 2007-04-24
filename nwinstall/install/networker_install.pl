#!/usr/bin/perl
###########
# networker_install.pl
# -Install packages on both nodes
# -configure cluster
# -insert servers files
# -get/set HostIDs
# -configure jukeboxes
#
#####

###### 
# Do not remove or disable without good documented reason.
#
use strict;
use warnings;
#
######



######
# Variable processing
# 
# Make our variables global
# any new config variable belongs here
#
use vars qw($NWPACKAGES $NSRSERVER @CLUSTERNODES $NWCLUSRG $HOSTIDFILE 
	$DSHELLTIMEOUT $INSTALLP $DSHELL $CLMOVE $CLRGINFO $TMPCMDFILE 
	$JBCONF $NWCLCONF $RCPPROG $CLUSTERSHAREDDIR $CLADDSERV 
	$CLSTARTSTOP $CLLSSERV $OURLOC ); 
#
######



#####
# set the defaults here and copy block to
# "/usr/ngscore/config/'progname'.conf" file
# 
## ## start config block ##
#
# our location
$OURLOC="/usr/ngscore";	#
#
# NetWorker packages location
$NWPACKAGES="$OURLOC/sw/networker";
# 
# the Name of the clustered
# NetWorker server
$NSRSERVER="sdp_nsr";
#
# the names of the cluster nodes primary node first
@CLUSTERNODES=("sdp1","sdp2");
#
# NetWorker Cluster RG
$NWCLUSRG="NetWorker_RG";
#
# location of the networker hostid file
$HOSTIDFILE="/nsr/res/hostids";
#
# time out for dsh command  adjust as necessary
$DSHELLTIMEOUT="180";
#
# rcp program..  could be scp if so inclined
$RCPPROG="/usr/bin/rcp";
#
# the name of the shared cluster mount point
# for NetWorker
$CLUSTERSHAREDDIR="/nsr_shared_mnt_pt";
#
# Cluster Start/Stop script
$CLSTARTSTOP="/usr/bin/nw_hacmp.lc";
#
## ## end config block ##


##### read in config files
if ( -e "../config/networker_install.conf") { 
	no strict 'refs';
	open ( CONF, "../config/networker_install.conf") || die "cannot open config: $!\n";
	my $conf = join "", <CONF>; 
	close CONF;
	eval $conf;
	die "Couldn't eval config file: $@\n" if $@;

	print "\n\nconfig file loaded\n";
} else {print "\n\nConfig file not found, using defaults\n";}
#####


print "Installer root: $OURLOC\n";

#####
# open logfile
open ( LOG, ">> $OURLOC/log/networker_install.log") || die "cannot open logfile $OURLOC/log/networker_install.log: $!\n";
#
# redirect STDOUT and STDERR to LOG with weird typeglob magic
*STDERR = *LOG;
*STDOUT = *LOG;
#####

#######
# Don't touch these without good reason
# 
#
# installp path
$INSTALLP="/usr/sbin/installp";
#
# dsh path and usage
# -t: timeout -- adjust as needed
$DSHELL="/usr/bin/dsh -t $DSHELLTIMEOUT";
#
# cluster move command: clRGmove
# -s false: specify actions on the primary node
# -m: move
# -g: Resource Group
# -n: node
$CLMOVE="/usr/es/sbin/cluster/utilities/clRGmove -s false -m ";
# Cluster RG Info command
# -s: colon delimited
#
$CLRGINFO="/usr/es/sbin/cluster/utilities/clRGinfo -s";
#
# Set the temp command file for the nsradmin command
# used in HostID generation
$TMPCMDFILE="/tmp/nsradm.tmp";
#
# jukebox expect script name
$JBCONF="$OURLOC/install/jukebox_config.exp";
# 
# cluster expect script name
# this script needs to be on both servers
#
$NWCLCONF="$OURLOC/install/cluster_config.exp";
#
# the add server command
$CLADDSERV="/usr/es/sbin/cluster/utilities/claddserv";
#
# the cllsserv command
$CLLSSERV="/usr/es/sbin/cluster/utilities/cllsserv";
#
##### end variable defaults




#####
#
#
print "\n\n\nStarting Install\n\n";
#
#####


##########
#
# common subroutines
#

######
# move_clnode()
#
# Subroutine to move the clusternode from one
# HACMP cluster node to another.
# takes the clusternode and resourcegroup as 
# inputs and returns the current node
#
sub move_clnode {
	#
	#
	my $sclnode = $_[0];
	my $sclrg = $_[1];
	
	# move the cluster and capture the output
	# cluster move command: clRGmove
	# -s false: specify actions on the primary node
	# -m: move
	# -g: Resource Group
	# -n: node
	print "Relocate cluster Resource group $sclrg to $sclnode\n";
	open (CLMOVECMD,"$CLMOVE -g $sclrg -n $sclnode 2>&1|")|| die "failed:$!\n";
	# test case
	#open (CLMOVECMD,"cl_move_to_sdp2.txt");
	#
	# capture the output
	my @clmvnode_in=<CLMOVECMD>;
	#
	#DEBUG print "COMMAND OUTPUT\n $CLMOVE \n @clmvnode_in \n----------\n";
	# loop through the output and do the right thing
	foreach my $cmno (@clmvnode_in) { # Nota: cmno = cluster move node out
		chomp($cmno);
		if ($cmno =~ m/^ERROR.*/) {
			# this probably means that 
			# the cluster already on the node were moving to
			print "Cluster move command failure\n: @clmvnode_in\n";
			print "Is active cluster node already $cmno?\n\n";
			# we might want to do something 
			# like this 
			# $_[0] = $clmvnode_out
			# or even unset
			# my $clmvnode_out ="";
			next; # we can skip out here
		} ## end errorcatching if
		if  ($cmno =~ m/^Resource.*online.*/) {
			# success!
			print "Cluster relocated to node: $cmno\n";
			# pass the value back and get out of here
			return ($cmno);
		} ## ende erfolgschleife
		#
	} ## end $CLMOVE cmd output read loop 
} ## close move_clnode subroutine


######
# get_clnode()
#
# Subroutine to get current node location of
# a resource group.  takes the RG as an input
# and returns the current node
#
sub get_clnode {
	# loop through each Resource Group
	#networker_install.pl
	my $srg = "$_[0]";
	open ( RGINFO, "$CLRGINFO $srg 2>&1|") || die "$CLRGINFO failed: $!\n";
	#open ( RGINFO, "RGinfo_sdp2") || die "$CLRGINFO failed: $!\n";
	my @rgstatus=<RGINFO>;
	my $nloc_out;

	# loop through the status
	#
	print "Getting current node for the $srg Resource Group:";
	foreach my $statlin ( @rgstatus) {
		print "l";
		if ($statlin =~ m/^.*ONLINE.*/) {
		my @rgloc_out=(split(/:/,$statlin));
			# only worried about if the actual
			# RG exists on the system and 
			# where it is
			print "x";
                        $nloc_out= $rgloc_out[2];
			$nloc_out =~ s/^\s+//;
			$nloc_out =~ s/\s+$//;
		} else {
			# don't care about offline nodes
			print".";
			next;
		} 
	print "\ncurrent node is $nloc_out\n";
	return($nloc_out);
	} ## close "ONLINE" check
	while (!$nloc_out) { 
		die "\nResource Group $srg not avalible or clustering not started\n"; 
	} ## close status loop check
} ## close rginfo_clnode subroutine
#
#
#######



###### 
# get_hostid()
#
# Subroutine to get the HostID out of networker automatically
# should return the hostid and accept the NetWorker server as a
# parameter
#
sub get_hostid {
	#
	# If there is an incoming passed value, 
	# concatinate "-s " to the front of $_[0] and 
	# send it to $nsrserver
	#
	my $nsradmsrv;
	if ($_[0]) {
		# if this exists we set the
		# the admin server
		$nsradmsrv="-s $_[0]";
	} else {
		# if it fails we could ignore
		# alternativly we can die
		die "\$NSRSERVER config Variable unset. Reset variable and rerun\n";
	} ## end passed value processing

	#
	# Create tempfile containing nsradmin commands
	open (NSRCMD, "> $TMPCMDFILE");
	print NSRCMD "show host id;\n\n";
	print NSRCMD "print type: NSR license;\n\n";
	print NSRCMD "quit\n";
	close (NSRCMD);
	
	# call nsrdadmin and use the tempfile
	#
	#print "$nsradmsrv\n";
	print "running nsradmin\n";
	
	open (NSRADM, "nsradmin $nsradmsrv -i $TMPCMDFILE 2>&1|") || die "Cannot start nsradmin: $!\n";
	my @hostid_in=<NSRADM>;
	close (NSRADM);

	# remove the temp command file
	#
	unlink ($TMPCMDFILE);
	#
	# clean up the hostid from nsradmin
	my @hostid_out;
	foreach my $hid (@hostid_in) {
		if ($hid =~ m/.*host.id.*/) {

			@hostid_out = split(/:/, $hid);
			$hostid_out[1] =~ s/\;//;
			$hostid_out[1] =~ s/\ //;
			chomp($hostid_out[1]);
		}
	}
	#
	if (!$hostid_out[1]) {die "no hostid found, stopped\n";}
	# return the hostid
	return "$hostid_out[1]";
} ## close get_hostid subroutine


#
# end subroutines
#####

#######
# networker_install.pm "main"
#
######
# Software install
#  Client, Storage node, Server, License Manager, NMC,  Man pages
#
# Install Networker softwhere on both nodes
# 
# 
foreach my $cn (@CLUSTERNODES) { # Nota: cn = clusternode
	chomp($cn);
	###
	# installp - install all packages from the given directory
	#  -a: apply packages
	#  -Q: "Quiet" - suppress errors or warnings
	#  -d: device or directory to install packages from
	#  -c: commit all specified updates
	#  -g: automatically install necessary updates	
	#  -X: expand any filesystem that requires additional room
	#  -Y: agrees to software license agreements
	#
	open (NWINSTALL, "$DSHELL -n $cn $INSTALLP -a -Q -d $NWPACKAGES -c -N -g -X -Y all 2>&1|")|| die "Cannot Install NetWorker: $!\n" ;
	my @inst_output = <NWINSTALL>;
	#
	# this can be uncommented if more detail desired.
	#print "$INSTALLP Output Node $cn:\n @inst_output\n\n";
	print "installing NetWorker on node: $cn";
	#
	# set some useful vars to hold our install checks
	my @inst_fail;
	my @inst_win;
	# check for failure
	# TODO this section needs tested 
	# all result values come from the installp man page
	#
	# Result 	Definition
	# SUCCESS 	The specified action succeeded.
	# FAILED 	The specified action failed.
	# CANCELLED 	Although preinstallation checking passed 
	# 		for the specified option, it was necessary 
	# 		to cancel the specified action before it was 
	# 		begun. Interrupting the installation process 
	# 		with Ctrl-c can sometimes cause a canceled action, 
	# 		although, in general, a Ctrl-c interrupt causes 
	# 		unpredictable results.
	#
	foreach my $instest (@inst_output) {
		#print "$instest\n";
		if ($instest =~ m/.*Pre-installation.*/g) {
			# just the header
			# nothing to see here
			print "h";
			next;
		} if ($instest =~ m/.*FAILED.*/g) {
			# catch errors
			print "Install Error: $instest\n";
			push (@inst_fail, $instest);
		} if ($instest =~ m/.*CANCELLED.*/g) {
			# no files
			print "Install Error: $instest\n";
			push (@inst_fail, $instest);
		} if ($instest =~ m/.*SUCCESS.*/g) {
			# install worked
			print "s";
			push (@inst_win, $instest);
		} if ($instest =~ m/.*Already.installed.*/g) {
			# install worked
			#print "\nNetWorker already installed, continuing\n";
			print "i";
			push (@inst_win, $instest);
		} else { #catchall: go back up trough the loop
			print "x";
			next;}
		} ## end install log processing loop
	
	# oops? } ## end eoreach
	# check to insure that all parts succeeded
	while (@inst_fail) {
		print "The following packages failed:\n@inst_fail\n";
		print "The following packages succeded:\n@inst_win\n";
		die "INSTALL FAILURE\n";
	} ## end install failure check

print "\n\nThe following packages succeded:\n@inst_win\n";

} ## end installer loop 
#
# end installer subsection
######


######
# configure cluster
#
#
#
print "starting NetWorker cluster script";
#
foreach my $cn (@CLUSTERNODES) { # Nota: $cn = cluster node
	chomp($cn);
	my $cc_success;
	print "\nconfiguring node:$cn";
	open ( NWCLCONFIG,"$DSHELL -n $cn $NWCLCONF $NSRSERVER $CLUSTERSHAREDDIR 2>&1|") || die "$!\n";

	my @nwcconfig_out = <NWCLCONFIG>;

	foreach my $ccline (@nwcconfig_out) {
		print ".";
		if ($ccline =~ m/^.*successfully.cluster-configured.*/) {
			print "\n$ccline\n";
			$cc_success = "s";
		}
		if ($ccline =~ m/.*already.configured.*/) {
		 	print "NetWorker clustering already configured\n";
		 	$cc_success = "c";
		}
		else { next; }
	}
	print "$cc_success\n" ;
	if ($cc_success lt 1) {
		die "\n\nNetWorker Cluster configuration script failed:\n @nwcconfig_out \n";
	} else {next;}
}

# start networker
# cheap and dirty, but should work
# 
my $curclnode = get_clnode($NWCLUSRG);
system ("$DSHELL -n $curclnode $CLSTARTSTOP start") ;
# nasty bug makes die() not work
if ($?) {die "command $DSHELL -n $curclnode $CLSTARTSTOP start failed: $?\n";}

#
# end configure cluster subsection
######


######
# get/set HostIDs
#
my %hostids;
my @hostids;


print"Determining cluster hostid:\n";

# Now loop through the list of clusternodes
# we don't need to do this with arrays of arrays, but 
# it allows us to print up a nice report when we're done.
#
foreach my $clnode ( @CLUSTERNODES ) {
	# 
	# set initial curnode
	my $curnode = get_clnode($NWCLUSRG);
	#
	# does the cluster need moved?
	if ( $clnode ne $curnode) {
		print "\nthe current node of $NWCLUSRG is: $curnode\nMoving node to $clnode\n";
		# yes? then shut down NetWorker
		system ("$DSHELL -n $curnode $CLSTARTSTOP stop");
		# nasty bug makes die() not work
		if ($?) {die "command $DSHELL -n $curclnode $CLSTARTSTOP stop failed: $?\n";}
		sleep(20);
		# move_clnode
		move_clnode($clnode,$NWCLUSRG);
		# 
		system ("$DSHELL -n $clnode $CLSTARTSTOP start");
		# nasty bug makes die() not work
		if ($?) {die "command $DSHELL -n $curclnode $CLSTARTSTOP start failed: $?\n";}
		# give the app some time to come up
		sleep (90);
		# 
		# update the current node
		$curnode = get_clnode($NWCLUSRG);
	} 
	# call for each cluster node
	my $hostid = get_hostid($NSRSERVER);
	#print $hostid;
	#
	push(@{$hostids{$clnode}},$hostid);
} ## close foreach()
#
# create a plain array..  there is probably a cheaper way
foreach my $clnode ( @CLUSTERNODES ) {
	print "$clnode hostid: @{$hostids{$clnode}}\n" ;
	push (@hostids, @{$hostids{$clnode}});	

} ## close foreach()#

# turn into our hostids file format
my $hostid_out = join (":",@hostids); 


print "writing hostid file to $HOSTIDFILE\n ";
#create hostid file
open (HOSTID,">$HOSTIDFILE") || die "$!\n";
print HOSTID "$hostid_out";
close (HOSTID);
print "$HOSTIDFILE written\n ";

# Move hostid file to both nodes
#

print "copying hostid file to $CLUSTERNODES[1]:$HOSTIDFILE\n ";
open (RSHOUT, "$RCPPROG $HOSTIDFILE $CLUSTERNODES[1]:$HOSTIDFILE 2>&1|") || die "$RCPPROG failed: $!\n"; 

my @rsh_out = <RSHOUT>;

foreach my $rshline (@rsh_out) {
	if ($rshline =~ m/^.*NOT.FOUND.*/) {
		die "ERROR: $rshline\n";
	}else {return(0);}
} ## end rsh log processing

print "hostid file copied\n";


# restart networker

print"Restarting NetWorker\n";
#
# this is lazy, but it will work
my $curnode = get_clnode($NWCLUSRG);
system ("$DSHELL -n $curnode $CLSTARTSTOP stop");
# nasty bug makes die() not work
if ($?) {die "command $DSHELL -n $curclnode $CLSTARTSTOP stop failed: $?\n";}

system ("$DSHELL -n $curnode $CLSTARTSTOP start");
# nasty bug makes die() not work
if ($?) {die "command $DSHELL -n $curclnode $CLSTARTSTOP start failed: $?\n";}
# get hostid and send somewhere
#
#
my $clhostid_out = get_hostid($NSRSERVER);
print ("NetWorker Cluster composite hostid: $clhostid_out\n");
# end get/set HostIDs subsection
######



######
#
# Configure jukebox

print "Configuring Jukebox\n";

open ( JBCONFIG,"$JBCONF $NSRSERVER 2>&1|") || die "$!\n";

my @jbconfig_out = <JBCONFIG>;

foreach my $jbline (@jbconfig_out) {
	if ($jbline =~ m/^.*added.*/) {
		print "$jbline\n";
	}
	if ($jbline =~ m/^.*cannot.connect.*/){
		die "@jbconfig_out \n"
	}
	if ($jbline =~ m/^.*RPC.error.*/){
		die "@jbconfig_out \n" 
	}
	if ($jbline =~ m/^.*RAP.error.*/){
		die "@jbconfig_out \n" 
	}else { next;}
} ## end jbconfig log processing
#
print "@jbconfig_out\n";
# end configure jukebox subsection
######

print "NetWorker Configured\n\n";

close (LOG);
