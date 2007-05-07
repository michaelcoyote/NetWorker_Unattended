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
print"select		Pool\n";


my %keyed_poollist;
my $pkey=1;
foreach my $pool (@NWPOOLS) {
	${keyed_poollist{$pkey}} = [] unless exists ${keyed_poollist{$pkey}}; 
	push(@{$keyed_poollist{$pkey}} => $pool);
	

	print"  $pkey		$pool\n";


}
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
	if ($jb_ln =~ m/.*error.*/) {die "jukebox error: @nsrjb_in\n";}
    	if ($jb_ln =~ m/^\s*(\d+): (.{13})(.{9})(.{8})/) {
		my($slot,$label,$pool,$barcode)=($1,$2,$3,$4);
		$label =~ s/\s+$//;
		$label =~ s/\*$//;
		$barcode =~ s/\s+$//;
		
		if ($label =~ /^\w/) { 
			if ($label !~ /^.{6,8}$/) { 
				die "nsrjb: bad label \"$label\"\n\t$_\n";
			} 
		}
		$label =~ s/-/unlabled/;
		if ($label !~ /^[A-z0-9]{6,8}$/) { 
			next;
		} else {
			# no reason to use this, but 
			# # defined() is a great thing to have 
			${keyed_slotlist{$slot}} = [] unless exists ${keyed_slotlist{$slot}}; 
			push(@{$keyed_slotlist{$slot}} => $barcode);
		}

format top =
slot #	Barcode	  NW Label
.
format =
@|||||@|||||||||@|||||||||||
$slot, $barcode, $label;
.
		write;

	}
}
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
	## check the hash position for existance
	if (!defined(@{$keyed_slotlist{$input}})) {
		print "\nno such slot, please select a listed set or press e to exit\n";
		next;
	} if (defined(@{$keyed_slotlist{$input}})) {
		print "\nyou selected: $input\n";
		$loopt=0;
	}


}



system("nsrjb -s $NSRSERVER -v -b @{$keyed_poollist{$input}} -S $input") ||die "$!\n";



#####
# 
