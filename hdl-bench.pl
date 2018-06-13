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
			if ($ports_raw[$i][$j] =~ /^(to|downto)$/){
				$ports_raw[$i][$j] = " " . $ports_raw[$i][$j] . " ";
			}
			# Add
			$ports[$i][2] .=  $ports_raw[$i][$j];
		}
	}
	# Remove semicolon if there is one at the end
	$ports[$i][2] =~ s/;//;

	# Check type to see its size in case of vectors
	# Find vectors 
	if ($ports[$i][2] =~ /[0-9]+ (downto|to) [0-9]+/i){

		# Get the slice description
		my($temp) = $ports[$i][2] =~ /([0-9]+ (downto|to) [0-9]+)/i;

		# Find first element index
		my($temp1) = $temp =~ /([0-9]+)/;
		# Remove first index
		$temp =~ s/([0-9]+)//;
		# Get second index
		my($temp2) = $temp =~ /([0-9]+)/;

		# Get the size and store it in $ports[$i][3]

		if ($temp1 > $temp2){
			$ports[$i][3] = $temp1 - $temp2 + 1;
		}
		else {
			$ports[$i][3] = $temp2 - $temp1 + 1;
		}

	} else{
		# We consider that it's not a vector so size is 1
		$ports[$i][3] = 1;
	}

} # End port scan


##
# Ports storage in @ports :
# $ports[$i][0] -> Port Name
# $ports[$i][1] -> Direction
# $ports[$i][2] -> Type
# $ports[$i][3] -> Number of bits
##

## Detect if the ports of the DUT include clocks
my @clocks;
my $cpt = 0;

# Loop over all ports to find clocks
for (my $i = 0; $i<@ports; $i++){
	# Check if it contains _Clk (case insensitive)
	if ($ports[$i][0] =~ /_Clk/i){
		# Also check that it's an input of DUT, not an output
		if ($ports[$i][1] =~ /in/i){

			$clocks[$cpt] = $ports[$i][0];
			$cpt++;

		}
	}
}

## Detect if the ports contain resets (only looking for active low resets of type reset_n)
my @resets;
$cpt = 0;

# Loop over to find resets
for (my $i = 0; $i<@ports; $i++){
	# Check if it contains _Clk (case insensitive)
	if ($ports[$i][0] =~ /reset_n/i){
		# Also check that it's an input of DUT, not an output
		if ($ports[$i][1] =~ /in/i){

			$resets[$cpt] = $ports[$i][0];
			$cpt++;

		}
	}
}

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

	# Print: signal + portname + : + type
	# + := + init value (if an input of DUT)

	$architecture_head .= "signal " . $ports[$i][0] . " : " .  $ports[$i][2];

	# Check if it's an input
	if ($ports[$i][1] eq "in"){
		$architecture_head .= " := ";
		if ($ports[$i][3] == 1){
			$architecture_head .= "'0'";
		} else {
			$architecture_head .= "(others => '0')";
		}
	}

	$architecture_head .= ";\n";

	# MAYBEDO: instead of assigning literals as init values, assign it to constants.
	# These constants (one for each input of the DUT) can be created in a special file and assigned to literal values there.
	# This could be an option when generaing the script (as it can be cumbersome if not needed).

} 

$architecture_head .= "\n";

## Add constant declarations (if any)

if (@clocks > 0 || @resets>0){

	$architecture_head .= "---------------------------------------------------------------------------------\n";
	$architecture_head .= "-------------------------- Constant declarations --------------------------------\n";
	$architecture_head .= "---------------------------------------------------------------------------------\n\n";

}

if (@clocks > 0){

	$architecture_head .= "-- CLOCKS --\n";

	for (my $i = 0; $i<@clocks; $i++){
		# For each clock, create a constant for its period (NAME_CLK_PERIOD)
		$architecture_head .= "constant " . $clocks[$i] . "_PERIOD : time := 100 ns; -- 10 MHz\n";
	}

	$architecture_head .= "\n";

}

if (@resets> 0){

	$architecture_head .= "-- RESETS --\n";
	$architecture_head .= "constant RESET_TIME : time := 1 ms;\n";

	# MAYBEDO: in case of a single clock, make the default reset time 10 times the clock period.
	# MAYBEDO: in case of multiple clocks, take the slowest.

	# MAYBEDO: allow for multiple reset times: but will need as many processes as resets, or 
	# some math on the reset times in a single process.
	# And is there really an interest ?

	$architecture_head .= "\n";

}



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

### Add TB signal generation processes

if (@clocks > 0 || @resets>0){

	$architecture_body .= "---------------------------------------------------------------------------------\n";
	$architecture_body .= "--------------------- Clock and Reset Generation Processes ----------------------\n";
	$architecture_body .= "---------------------------------------------------------------------------------\n\n";

}

## Clock generation processes
if (@clocks > 0){

	$architecture_body .= "-- CLOCK --\n";
	$architecture_body .= "clock_generation : process(" . join(", ", @clocks) . ")\n";
	$architecture_body .= "begin\n\n";

	# Loop over the clocks
	for ($i=0; $i<@clocks; $i++){
		$architecture_body .= "\t" . $clocks[$i] . " <= not " . $clocks[$i] . " after (" . $clocks[$i] . "_PERIOD / 2);\n";
	}

	$architecture_body .= "\nend process clock_generation;\n\n";

}

## Reset generation processes
if (@resets > 0){

	$architecture_body .= "-- RESET --\n";
	$architecture_body .= "reset_generation : process\n";
	$architecture_body .= "begin\n\n";
	# Loop over the resets
	for ($i=0; $i<@resets; $i++){
		$architecture_body .= "\t" . $resets[$i] . " <= '0';\n";
	}
	$architecture_body .= "\twait for RESET_TIME;\n";
	for ($i=0; $i<@resets; $i++){
		$architecture_body .= "\t" . $resets[$i] . " <= '1';\n";
	}
	$architecture_body .= "\twait;\n\n";

	$architecture_body .= "end process reset_generation;\n\n";

}






# Architecture body end
$architecture_body .= "end " . $tbarchiname . ";\n";

print $outputfile $architecture_body;

