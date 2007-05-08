#!/usr/bin/perl
#
#
#
###### 

use vars qw( $NSRSERVER );


# Do not remove or disable without good documented reason.
#
use strict;
use warnings;
#####
# 
## ## start config block ##
#
# the Name of the clustered
# NetWorker server
$NSRSERVER="sdp_nsr";
#
#
#
$DEBUG=0;
#
##### end variable default

#####
#
#
#


open (JBIN, "nsrjb -s$NSRSERVER -C 2>&1|") || die "problem with nsrjb\n";


my @nsrjb_in = <JBIN>;

print "@nsrjb_in\n" if $DEBUG;
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
		$barcode =~ s/\s+$//; ## also remove whitespace
		# 
		# check for validity 
		# this section could be cleaned up
		if ($label =~ /^\w/) {
			#
			# labels are 6-8 chars long, right?
			if ($label !~ /^.{6,8}$/) { 
				die "nsrjb: bad label \"$label\"\n\t$_\n";
			} 
		}
		#
		# 
		$label =~ s/-/unlabled/; ## identify unlabeled tapes perhaps collapse with "*" above
		#
		# final test for validity.  
		# Insure that the label is all alpha numeric
		#
		if ($label !~ /^[A-z0-9]{6,8}$/) { 
			next;
		} else {
			# press the barcode into a hash keyed by slot number.
			# this will be usefule when we need to display both 
			# then select an avalible tape. there's probably a simpler 
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
	# 
	print 'Select the slot # or press e to exit [e]: ';
	print "\n";
	$| = 1;			# force a flush after our print
	$input = <>;		# get the input 
	chomp($input);
	$input="e" if (!$input);
	if ($input eq "e") {
		exit;}
	## check the hash position for existance
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
# and here you just do a simple withdraw on the tapes by slot
system("nsrjb -s $NSRSERVER -v -w  -S $input") ||die "$!\n";

#####
# 
