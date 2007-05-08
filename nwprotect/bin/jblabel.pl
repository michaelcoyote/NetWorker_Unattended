#!/usr/bin/perl
#
#
#
###### 

use vars qw( $NSRSERVER @NWPOOLS );


# Do not remove or disable without good documented reason.
#
use strict;
use warnings;
#####
# set the defaults here and copy block to your conf file
# 
## ## start config block ##
#
# the Name of the clustered
# NetWorker server
$NSRSERVER="sdp_nsr";
#
# allowable pools
@NWPOOLS=qw(bootstrap MainDBbackup );
#
##### end variable default

#####
#
#
#
#
# cheap and dirty header for the list of pools generated below 
print"select		Pool\n";


my %keyed_poollist;
my $pkey=1;
#
# iterate through our list of pools
foreach my $pool (@NWPOOLS) {
	#
	# create a keyed list of pools for use in selection below
	${keyed_poollist{$pkey}} = [] unless exists ${keyed_poollist{$pkey}}; 
	push(@{$keyed_poollist{$pkey}} => $pool);
	# 
	# print out each key number and pool in turn
	print"  $pkey		$pool\n";
	#
	# increment our key
	$pkey++;
	#
}

#
# pool selection, while loop with a test
# we use defined() to insure existance of the pool selection
# and can escape with an "e"
my $pinput;
my $ploopt=1;
while ($ploopt){
	print 'Select the pool #: ';
	print "\n";
	$| = 1;			# force a flush after our print
	$pinput = <>;		# get the input 
	chomp($pinput);
	$pinput="e" if (!$pinput);
	if ($pinput eq "e") {
		exit;}
	## check the hash position for existance
	if (!defined(@{$keyed_poollist{$pinput}})) {
		print "\nno such pool, please select a listed set or press e to exit\n";
		next;
	} if (defined(@{$keyed_poollist{$pinput}})) {
		print "\nyou selected: $pinput: @{$keyed_poollist{$pinput}}\n";
		$ploopt=0;
	}


}




open (JBIN, "nsrjb -s$NSRSERVER -C 2>&1|") || die "problem with nsrjb\n";


my @nsrjb_in = <JBIN>;

# print "@nsrjb_in\n";
my %keyed_slotlist;

foreach my $jb_ln (@nsrjb_in){
	#
	# trap error conditions in the nsrjb output
	if ($jb_ln =~ m/.*error.*/) {die "jukebox error: @nsrjb_in\n";}
	# 
	# split up the output of nsrjb.  Until emc provides us with a
	# flag to output nsrjb in comma delim format, we're stuck with this
    	if ($jb_ln =~ m/^\s*(\d+): (.{13})(.{9})(.{8})/) {
		#             ^$1     ^$2    ^$3   ^$4
		my ($slot,$label,$pool,$barcode)=($1,$2,$3,$4);
		$label =~ s/\s+$//; ## remove whitespace 
		$label =~ s/\*$//; ## remove "*" 
		$label =~ s/-/unlabled/; ## identify unlabeled tapes perhaps collapse with "*" above
		$barcode =~ s/\s+$//; ## also remove whitespace
		#
		# test for validity.  
		# insure that the label is all 
		# alpha numeric 6-8 chars long
		if ($label !~ /^\w{6,8}$/) {
			# if it's not, we skip the line
			next;
		} else {
			# press the barcode into a hash keyed by slot number.
			# this will be useful when we need to display both 
			# then select an avalible tape. there  might be a simpler 
			# way,  but defined() is a great thing to have 
			#
			# set everything up if it hasn't been
			${keyed_slotlist{$slot}} = [] unless exists ${keyed_slotlist{$slot}};
			# push the data on here
			push(@{$keyed_slotlist{$slot}} => $barcode);
		}
		#
		# set up a nice pretty format for our output.  
		# This scales to larger jukeboxes well
		# we could include pool here, but decided not 
		# at this time
		#
format top =
slot #	Barcode	  NW Label
.
format =
@|||||@|||||||||@|||||||||||
$slot, $barcode, $label;
.
		# use the format here
		write;

	}
}
#
# ok, do the selection of tape here
# simple while loop with test.  loop 
# through until somone hits e to exit 
# or selects a valid slot/barcode
#
# setup vars
my $input;
my $loopt=1;
while ($loopt){
	print 'Select the slot # or press e to exit [e]: ';
	print "\n";
	$| = 1;			# force a flush after our print
	$input = <>;		# get the input 
	chomp($input);
	$input="e" if (!$input);
	if ($input eq "e") {
		exit;}
	# check the hash position for existance
	# note that defined() is a great thing to have
	if (!defined(@{$keyed_slotlist{$input}})) {
		print "\nno such slot, please select a listed set or press e to exit\n";
		next;
	} if (defined(@{$keyed_slotlist{$input}})) {
		print "\nyou selected: $input\n";
		$loopt=0;
	}


}

#
#
# set pool type and label by slot
# the keyed hash comes in handy here for setting the pool type
system("nsrjb -s $NSRSERVER -v -b @{$keyed_poollist{$input}} -S $input") ||die "$!\n";



#####
# 
