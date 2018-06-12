###############################################
# VHDL Testbench structure generator

# Use: "perl hdl-bench.pl VHDLfile.vhd"
###############################################


# Use strict and warnings
use strict;
use warnings;


## Get VHDL file name

my $hdlfilename;

# Check if script is lauched with parameters
if (@ARGV) {

	$hdlfilename = $ARGV[0];

	# MAYBEDO: check validity of file: has extension and is .vhd or .vhdl.

	print "Input HDL file: $hdlfilename \n";

} else {

    print "No input file entered as parameter \n";
    exit;

}


## Open file and get content

open(my $inputfile,  "<",  $hdlfilename)  or die "Can't open input file $!";

# Slurp it
#my @inputlines = <$inputfile>;


## Get basic info on HDL file

# The entity name if DUT
my $entityname; 

# Extract name of entity
while (<$inputfile>) {     # assigns each line in turn to $_
     #print "Just read in this line: $_";
    if (index($_, "entity") != -1) {

	    #print "$_ contains entity \n";

	    # MAYBEDO: check that this word only appears once.
	    # MAYBEDO: refine the search with regex to avoid matching words containing entity (e.g. "divider_entity").

	    # MAYBEDO: in case of multiple entities, find which one is top-level

	    # Line with Entity keyword is found: split and get the second element (the one after entity)
	    # to get the name of the entity
	    $entityname = (split / /, $_)[1];

	    # MAYBEDO: instead of accessing directly using the index (1, the 2nd element),
	    # it would be more robust to access the index following the index of entity keyword.

	    #print $entityname . "\n";
	} 

	#MAYBEDO: take care of the case where Entity is not found

}

 ## Get the port map

# Set pointer to top again
 seek $inputfile, 0, 0;

# Helps see where in the code architecture the pointer is
my $loc = "out";

# Store the port declarations
my @ports_raw;
my @ports;

# Counter 
my $i=0;

# Scan file again
while (<$inputfile>) {     # assigns each line in turn to $_

	my $findentity = "entity ". $entityname;

	# We are iside the entity declaration (the DUT entity)
	if ($_ =~ /$findentity/){
		$loc = "entity";
	}

	# We are in its port map
	if ($_ =~ /port\(/ && $loc eq "entity"){
		$loc = "entityportmap";
		$i = 0;
	}

	# We exit the port map
	if ($_ =~ /\(,/ && $loc eq "entityportmap"){
		$loc = "entity";
	}

	# We exit the entity declaration
	if ($_ =~ /end/ && $loc eq "entity"){
		$loc = "out";
	}

	# Let's check the I/O in the port map
	if ($loc eq "entityportmap"){

		# Regex: [a-zA-Z0-9_]+\s+:\s+(?i)(in|out)
		# Matches the following sequence: 
		# >> a word of unlimited size containing letters (upper or smaller case), words and underscore then whitespace(s),
		# >> then a colon, then whitespa(s), then "in", "out" or "inout" (case insensitive)

		# This, whithout expending to the type (and list all types and subtypes), matches a port element easily

		if($_ =~ /[a-zA-Z0-9_]+\s+:\s+(?i)(in|out|inout)/){

			# Port element: split it and copy it
			$ports_raw[$i] = [split(/\s+/, $_)];

			# print "@$_\n" for @ports[$i];
			# print "\n";

			$i ++;

		}

	}

}

# print @ports . "\n";
# print join("\n",@ports),"\n"; 

## Rework the ports to make it more usable

# Scan all ports
for (my $i = 0; $i<@ports_raw; $i++){

	# Remap name and direction
	$ports[$i][0] = $ports_raw[$i][1];
	$ports[$i][1] = $ports_raw[$i][3];

	# For type, we must check if it was split (because it contained whitespaces)
	# If it's complete: [4] is last element so size is 5
	if (@{$ports_raw[$i]} == 5){
		# It's complete: copy to @ports
		$ports[$i][2] = $ports_raw[$i][4];
	} else {
		# Since it's not complete, we have to concatenate elements till the end
		for (my $j=4; $j<@{$ports_raw[$i]}; $j++){
			# In case of a vector, some spaces must be added
			if ($ports_raw[$i][$j] =~ /(upto|downto)/){
				$ports_raw[$i][$j] = " " . $ports_raw[$i][$j] . " ";
			}
			# Add
			$ports[$i][2] .=  $ports_raw[$i][$j];
		}
	}
	# Remove semicolon if there is one at the end
	$ports[$i][2] =~ s/;//;

}


##
# Ports storage in @ports :
# $ports[i][0] -> Port Name
# $ports[i][1] -> Direction
# $ports[i][2] -> Type
##



## Create the output testbench file

my $tbfilename = $entityname . "_TB.vhd";

print $tbfilename . "\n";

open(my $outputfile, ">",  $tbfilename) or die "Can't create/open output file: $!";


## Write header in TB file

my $header = "---------------------------------------------------------------------------------\n";
$header .= "-- Testbench file for entity: " . $entityname . "\n";
$header .= "-- \n-- \n-- \n";
$header .= "---------------------------------------------------------------------------------\n\n";

print $outputfile $header;

## Add libraries

my $libs = "library IEEE;\n";
$libs .= "use IEEE.std_logic_1164.all;\n";
$libs .= "use IEEE.numeric_std.all;\n\n";

print $outputfile $libs;

## Declare testbench entity

my $tbentityname = $entityname . "_TB";

my $tbentity = "entity " . $tbentityname . " is\n";

# MAYBEDO: add empty generic declaration

$tbentity .= "\n";
$tbentity .= "end " . $tbentityname . ";\n\n";

print $outputfile $tbentity;

### Architecture of TB

my $tbarchiname = "behavorial";

## Architecture "header": from declaration start (architecture xxxx of xxxx is) to begin (not included)

my $architecture_head = "architecture " . $tbarchiname . " of " . $tbentityname . " is\n\n";

$architecture_head .= "---------------------------------------------------------------------------------\n";
$architecture_head .= "--------------- Signal Declarations for Connections with UUT --------------------\n";
$architecture_head .= "---------------------------------------------------------------------------------\n\n";

# Loop over all ports
for (my $i = 0; $i<@ports; $i++){

	#$architecture_head .= "signal " . $ports[$i][1] . " : " . $ports[$i][4] . ";\n";

	# Print: signal + portname + : + type + := + init value

	$architecture_head .= "signal " . $ports[$i][0] . " : " .  $ports[$i][2] . ";";

	$architecture_head .= "\n";

} 

$architecture_head .= "\n";

print $outputfile $architecture_head;

## Architecture body: from "begin" to "end"

# Architecture body start
my $architecture_body = "begin\n\n";

# Instantiate UUT: info
$architecture_body .= "---------------------------------------------------------------------------------\n";
$architecture_body .= "---------------- Instantiate UUT: " . $entityname . "\n";
$architecture_body .= "---------------------------------------------------------------------------------\n\n";

$architecture_body .= $entityname . "_0 : entity work." . $entityname . "\n";
$architecture_body .= "\tport map(\n";

## Add the port map

# Loop over all ports
for (my $i = 0; $i<@ports; $i++){

	$architecture_body .= "\t\t";

	# Add name of port and affectation to the same name signal
	$architecture_body .= $ports[$i][0] . " " . "=>" . " " . $ports[$i][0];

	# Unless port is the last, add a coma
	if ($i != @ports - 1){
		$architecture_body .= ",";
	}

	$architecture_body .= "\n";
}

# MAYBEDO: insert tabs inside port declaration to align elements


$architecture_body .= "\t);\n\n";


# Architecture body end
$architecture_body .= "end " . $tbarchiname . ";\n";

print $outputfile $architecture_body;

