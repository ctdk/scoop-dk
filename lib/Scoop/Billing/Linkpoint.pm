package Scoop;
use strict;
my $DEBUG = 0;

# Linkpoint.pm
#
# CC processing module for the Linkpoint LPERL wrapper.
# See doc/Linkpoint.howto.


# Process a full payment immediately.
# Uses the LPERL ApproveSale function to do
# pre and post-auth at the same time.
sub cc_immediate_payment {
	my $S = shift;
	my $price = shift;
	my $args = shift;
	
	unless ($price) {
		$S->{CC_ERR} .= qq|No price received.<br>|;
	}

	# Make a new lperl
	my $lperl = new LPERL($S->{CONFIG}->{lbin_location}, "FILE", $S->{CONFIG}->{lbin_tmp_dir});
	
	my $transaction_hash = $S->lperl_input_hash($price, $args);
	
	
	# Ok, go ahead then
	my %cc_result;
	unless ($S->{CC_ERR}) {
		%cc_result = $lperl->ApproveSale($transaction_hash);
	}
	
	return %cc_result;
}


# cc_pre_auth: Pre-authorize a transaction. 
sub cc_pre_auth {
	my $S = shift;
	my $price = shift;
	my $in = shift;
	
	# Make a new lperl
	my $lperl = new LPERL($S->{CONFIG}->{lbin_location}, "FILE", $S->{CONFIG}->{lbin_tmp_dir});
	
	my $transaction_hash = $S->lperl_input_hash($price, $in);
	
	# Ok, go ahead then
	my %cc_result;
	unless ($S->{CC_ERR}) {
		%cc_result = $lperl->CapturePayment($transaction_hash);
	}
	
	return %cc_result;
}

# $orders is a reference to an array of hashes which must
# include, on input, {orderID => $oid}. On return, 
# $orders is updated with statusCode and eerorMessage
sub cc_post_auth {
	my $S = shift;
	my $orders = shift;
	
	# Finish sale
	my $transaction_hash = {
		hostname		=>	$S->{CONFIG}->{linkpt_host},
		port			=>	$S->{CONFIG}->{linkpt_port},
		storename		=>	$S->{CONFIG}->{linkpt_store},
		keyfile			=>	$S->{CONFIG}->{linkpt_keyfile},
		orders			=>	$orders
	};

	my $lperl = new LPERL($S->{CONFIG}->{lbin_location}, "FILE", $S->{CONFIG}->{lbin_tmp_dir});

	my $processed = $lperl->BillOrders($transaction_hash);

	return $transaction_hash->{orders};
}



# Create input hash for LPERL functions.
#
sub lperl_input_hash {
	my $S = shift;		
	my $price = shift;
	my $in = shift;
		
	# Pull out numeric part of address, if possible
	my $addrnum = $in->{baddr1};
	$addrnum =~ s/^(\d+).*$//g;
	
	my $transaction_hash = {
		hostname		=>	$S->{CONFIG}->{linkpt_host},
		port			=>	$S->{CONFIG}->{linkpt_port},
		storename		=>	$S->{CONFIG}->{linkpt_store},
		keyfile			=>	$S->{CONFIG}->{linkpt_keyfile},
		chargetotal		=>	$price,
		cardnumber		=>	$in->{cardnumber},
		expmonth		=>	$in->{expmonth},
		expyear			=>	$in->{expyear},
		bname			=>	"$in->{fname} $in->{lname}",
		baddr1			=>	$in->{baddr1},
		baddr2			=>	$in->{baddr2},
		bcity			=>	$in->{bcity},
		bstate			=>	$in->{bstate},
		bcountry		=>	$in->{bcountry},
		bzip			=>	$in->{bzip},
		phone			=>	$in->{phone},
		ip				=>	$S->{REMOTE_IP},
		mototransaction	=>	'ECI_TRANSACTION',
		cvmindicator	=>	'CVM_NotProvided'
	};
	
	# Use for testing purposes. Comment out in a live trans
	#$transaction_hash->{result} = 'GOOD';
	
	if ($addrnum) {
		warn "Addrnum is $addrnum\n";
		$transaction_hash->{addrnum} = $addrnum;
	}
	
	unless (
		$transaction_hash->{hostname} 	&&
		$transaction_hash->{port}		&&
		$transaction_hash->{storename}	&&
		$transaction_hash->{keyfile}	  ) {
		$S->{CC_ERR} .= qq|Server is not properly configured to process this transaction.<br>|;
	}
	
	return $transaction_hash;
}




1;
