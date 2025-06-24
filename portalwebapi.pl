#!/usr/bin/env perl
#
# Verison 0.8 28Aug2017
# Version 0.9 14Des2018
# Version 2.30 13.11.2024 Added remotecontroll for pumpe control (Rele)
# Version 2.4 12.12.2024 Added API for user/variables
#
#
#use utf8;
use Time::Piece;
use File::Basename;
use Net::Domain qw(hostfqdn);
use MIME::Base64;
use MIME::Lite;
use DBI;
use HTTP::Request;
use LWP::UserAgent;
use Dancer2;
use Data::Dumper;
set serializer => 'JSON';
set port         => 46000;
# 
use open ':utf8';

# config
my $PROGNAME='portalwebapi';
my $VERSION='2.40';

my $sensordatapath="/var/spool/7sense/sensordata/";
my $queuepath="/var/spool/7sense/queue/";
my $firmwarepath="/var/spool/7sense/firmware/";

my $errorreceivers='kjell.sundby@7sense.no';
my $sendinfolevel=1;
my $logfile="/var/log/7sense/$PROGNAME.log";
my $uucppath="/var/spool/uucppublic/";
my $mainbase_db="dbi:Pg:dbname=mainbase;host=localhost;port=5432";
my $dbuserid="admin_db"; my $dbpasswd="OnesNeser2!";
my $hostname=hostfqdn ();
# Declaring variables
my $default_limit=10000;
my $default_offset=0;
my $oid="";
my $serialnumber="";


# Open log files
add2log(3,"Deamon $PROGNAME version started $VERSION");# Info

# Open database
my $mainbase_db_ctl = DBI->connect($mainbase_db, $dbuserid, $dbpasswd, {AutoCommit => 1, RaiseError => 1 }) or die $DBI::errstr; 
#my $dbportalctl=DBI->connect('dbi:Pg:dbname=7portal;host=localhost;port=5432','admin_db','onesnes78', { RaiseError => 1 }) or die $DBI::errstr; 

add2log(4,"Opened databases successfully"); # Debug

#######################################################################
#
# API for Sensor units handling
#
post '/v1/sensorunits/access/grant' => sub {
	if (not defined params->{user_id} or not params->{serialnumber} or not params->{user_email} or not params->{changeallowed}){
		send_error("Missing parameter: needs user_id, serialnumber, user_email and changeallowed",400);
	}
	my $user_id = params->{user_id};
	my $serialnumber = params->{serialnumber};
	my $user_email = params->{user_email};
	my $changeallowed = params->{changeallowed};
	# Check if allowed to change
	if (not allowed2change($user_id,$serialnumber)){
		send_error("user_id: $user_id is not allowed to change $serialnumber",400);
	}
	# Find user_id via email
	my $sth = $mainbase_db_ctl->prepare("SELECT user_id from users where user_email='$user_email'");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my $rows=$sth->fetchrow_hashref();
	$sth->finish();
	$user_id=$rows->{user_id};
	if (!$user_id){
		# user with email not found
		send_error("User with email:$user_email is not found",400);
	}
	# Check if allready has access and delete
	$sth = $mainbase_db_ctl->prepare("DELETE FROM sensoraccess where user_id='$user_id' and serialnumber='$serialnumber'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	$sth->finish();
	# Grant access
	$sth = $mainbase_db_ctl->prepare("INSERT INTO sensoraccess (user_id,serialnumber,changeallowed) VALUES ($user_id,'$serialnumber',$changeallowed)");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	$sth->finish();
	return{ message =>"OK"};
};
del '/v1/sensorunits/access/delete' => sub {
	if (not defined params->{serialnumber} or not defined params->{user_id} or not defined params->{user_email}){
		send_error("Missing parameter: needs serialnumber,user_id and user_email)",400);
	}

	my $user_id = params->{user_id};
	my $serialnumber = params->{serialnumber};
	my $user_email = params->{user_email};
	# Check if allowed to change
	if (not allowed2change($user_id,$serialnumber)){
		send_error("user_id: $user_id is not allowed to change $serialnumber",400);
	}
	# Find user_id via email
	my $sth = $mainbase_db_ctl->prepare("SELECT user_id from users where user_email='$user_email'");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my $rows=$sth->fetchrow_hashref();
	$sth->finish();
	$user_id=$rows->{user_id};
	add2log(4," user_id: $user_id");
	if (!$user_id){
		# user with email not found
		send_error("User with email:$user_email is not found",400);
	}
	# delete record
	$sth = $mainbase_db_ctl->prepare("DELETE FROM sensoraccess where user_id='$user_id' and serialnumber='$serialnumber'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	$sth->finish();
	if ($result eq "0E0"){
		send_error("No record for user_email:$user_email and serialnumber=$serialnumber.",404);
  }else{
   	return{ message =>"OK"};
	}
};
get '/v1/sensorunits/access/list' => sub {
	if (not defined params->{serialnumber} and not defined params->{user_id}){
		send_error("Missing parameter: needs serialnumber user_id)",400);
	}
	
	my $user_id = params->{user_id};
	my $serialnumber = params->{serialnumber};
	my $db_where='';
	if ($serialnumber){
		$db_where="serialnumber='$serialnumber'";
	}else{
		$db_where="user_id='$user_id'";
	}
	my $sth = $mainbase_db_ctl->prepare("SELECT serialnumber,user_id,changeallowed from sensoraccess where $db_where");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	return{ 'result'=>\@dataset};
};
get '/v1/sensorunits/all' => sub {
    my $limit = params->{limit};
    my $offset = params->{offset};
    my $serialnumber = params->{serialnumber};
    my $sensorunit_id = params->{sensorunit_id};
    my $sensortype = params->{sensortype};
    my $sortfield = params->{sortfield};
    my $order_by="";
    if ($sortfield){$order_by="ORDER BY $sortfield"}
    my $db_where='';
    
    if ($serialnumber){$db_where="WHERE public.sensorunits.serialnumber = '$serialnumber'"}
    if ($sensorunit_id){
        if (!$serialnumber){
            $db_where.=" WHERE public.sensorunits.sensorunit_id='$sensorunit_id'";
        }else{
            $db_where.=" and public.sensorunits.sensorunit_id='$sensorunit_id'";
        }
    }   
    
    my $sth = $mainbase_db_ctl->prepare("SELECT
    public.sensorunits.serialnumber,
    public.sensorunits.custom_id,
    public.sensorunits.sensorunit_installdate,
    public.sensorunits.sensorunit_lastconnect,
    public.sensorunits.dbname,
    public.sensorunits.sensorunit_location,
    public.sensorunits.sensorunit_note,
    public.sensorunits.sensorunit_status,
    public.sensorunits.product_id_ref,
    public.sensorunits.customer_id_ref,
    public.sensorunits.helpdesk_id_ref,
    public.sensorunits.sensorunit_position,
    public.sensorunits.block,
    public.products.product_name,
    public.customer.customer_name,
    public.helpdesks.helpdesk_name,
    public.sensorunits.sensorunit_id
 
    FROM public.sensorunits
    INNER JOIN public.products ON (public.sensorunits.product_id_ref = public.products.product_id)
    INNER JOIN public.customer ON (public.sensorunits.customer_id_ref = public.customer.customer_id)
    INNER JOIN public.helpdesks ON (public.sensorunits.helpdesk_id_ref = public.helpdesks.helpdesk_id)
    $db_where $order_by
     ");
    
    $sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
    
    my @dataset=();
    while (my $row=$sth->fetchrow_hashref()){
        push (@dataset,$row);
    }
    $sth->finish();
    add2log(4,"Fetched (".scalar(@dataset).") queue records URL /v1/sensorunits/all");# debug
    return{ 'result'=>\@dataset};
 
};


get '/v1/sensorunits/list' => sub {
	my $limit = params->{limit};
	my $offset = params->{offset};
	my $user_id = params->{user_id};
	my $serialnumber = params->{serialnumber};
	my $productnumber = params->{productnumber};
	my $sensortype = params->{sensortype};
	my $sortfield = params->{sortfield};
	# find user via token
	if (not defined $user_id){$user_id=get_userid_from_token();}
	
	my $order_by="";
	if ($sortfield){$order_by="ORDER BY $sortfield"}
	my $db_where='';
	if (defined $user_id and $user_id ne ''){$db_where="WHERE public.sensoraccess.user_id = '$user_id'";}
	if ($serialnumber){
		if ( not $user_id or $user_id eq ''){
			$db_where.=" WHERE public.sensoraccess.serialnumber='$serialnumber'";
		}else{
			$db_where.=" and public.sensoraccess.serialnumber='$serialnumber'";
		}
	}	
	# If product number use 10 first chars in serialnumber
	if ($productnumber){
			$db_where=" WHERE substring(sensoraccess.serialnumber from 1 for 10)='$productnumber'";
	}
	# 
	add2log(4,"/v1/sensorunits/list db_where:$db_where");# debug
	my $sth = $mainbase_db_ctl->prepare("SELECT
    public.sensoraccess.serialnumber,
    public.sensoraccess.changeallowed,
    public.sensoraccess.user_id,
    public.products.product_name,
    public.products.product_description,
    public.products.productnumber,
    public.products.product_type,
    public.products.product_image_url,
    public.sensorunits.sensorunit_installdate,
    public.sensorunits.sensorunit_lastconnect,
    public.sensorunits.sensorunit_location,
    public.sensorunits.sensorunit_xpos,
    public.sensorunits.sensorunit_zpos,
    public.sensorunits.sensorunit_status,
    public.sensorunits.block,
    public.customertype.description,
    public.customertype.customertype,
    public.products.product_id,
    public.customertype.customertype_id,
    public.sensorunits.sensorunit_ypos,
    public.sensorunits.sensorunit_note,
    public.customer.customernumber,
    public.customer.customer_name,
    public.customer.customer_site_title,
    public.customer.customer_id,
    public.customer.customer_maincontact,
    public.documents.document_url,
    public.documents.document_name,
    public.helpdesks.helpdesk_phone,
		public.helpdesks.helpdesk_email
FROM public.sensoraccess
INNER JOIN public.sensorunits ON (public.sensoraccess.serialnumber = public.sensorunits.serialnumber)
INNER JOIN public.products ON (public.sensorunits.product_id_ref = public.products.product_id)
INNER JOIN public.customer ON (public.sensorunits.customer_id_ref = public.customer.customer_id)
INNER JOIN public.customertype ON (public.customer.customertype_id_ref = public.customertype.customertype_id)
INNER JOIN documents ON (products.document_id_ref=documents.document_id)
INNER JOIN public.helpdesks ON (public.sensorunits.helpdesk_id_ref = public.helpdesks.helpdesk_id)
$db_where $order_by
");
	
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	
	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") queue records URL /v1/sensorunits/list");# debug
	return{ 'result'=>\@dataset};

};

############### add/delete/update
post '/v1/sensorunits/add' => sub {
	if (not params->{serialnumber} or not params->{dbname} or not params->{product_id_ref} or not params->{customer_id_ref} or not params->{helpdesk_id_ref}){
		send_error("Missing parameter: needs at least serialnumber, dbname, product_id_ref, customer_id_ref, helpdesk_id_ref",400);
	}
	# Needed parameters
	my $serialnumber = params->{serialnumber};
	my $dbname = params->{dbname};
	my $product_id_ref = params->{product_id_ref};
	my $customer_id_ref = params->{customer_id_ref};
	my $helpdesk_id_ref = params->{helpdesk_id_ref};
	# option parameters
	my $sensorunit_installdate = params->{sensorunit_installdate} || '1970-01-01';
	my $sensorunit_lastconnect = params->{sensorunit_lastconnect} || '1970-01-01';
	my $sensorunit_location = params->{sensorunit_location} || '';
	my $sensorunit_note = params->{sensorunit_note} || '';
	my $sensorunit_position = params->{sensorunit_position} || '';
	my $sensorunit_status = params->{sensorunit_status} || '';

	# test if record already exists
	my $sth = $mainbase_db_ctl->prepare("SELECT serialnumber FROM sensorunits WHERE serialnumber='$serialnumber'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	if ($result ne "0E0"){
		add2log(2,"Record exists for serialnumber:$serialnumber.");# Info
		send_error("Record exists for serialnumber:$serialnumber",302);
	}


	add2log(4,"Adding record for serialnumber:$serialnumber with parameters dbname:$dbname, product_id_ref:$product_id_ref, customer_id_ref:$customer_id_ref, helpdesk_id_ref:$helpdesk_id_ref, sensorunit_installdate:$sensorunit_installdate, sensorunit_lastconnect:$sensorunit_lastconnect, sensorunit_location:$sensorunit_location, sensorunit_note:$sensorunit_note, sensorunit_position:$sensorunit_position, sensorunit_status:$sensorunit_status");# Info
	$sth = $mainbase_db_ctl->prepare( "INSERT INTO sensorunits 
	(serialnumber,dbname,product_id_ref,customer_id_ref,helpdesk_id_ref,sensorunit_installdate,sensorunit_lastconnect,sensorunit_location,sensorunit_note,sensorunit_position,sensorunit_status) 
	VALUES ('$serialnumber','$dbname',$product_id_ref,$customer_id_ref,$helpdesk_id_ref,'$sensorunit_installdate','$sensorunit_lastconnect','$sensorunit_location','$sensorunit_note','$sensorunit_position',$sensorunit_status)");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	return {result=>"OK"};
};

patch '/v1/sensorunits/update' => sub {
	if (not params->{serialnumber}){
		send_error("Missing parameter: needs at least serialnumber",400);
	}
	# Needed parameters
	my $serialnumber = params->{serialnumber};
	my $dbname = params->{dbname};
	my $product_id_ref = params->{product_id_ref};
	my $customer_id_ref = params->{customer_id_ref};
	my $helpdesk_id_ref = params->{helpdesk_id_ref};
	my $sensorunit_installdate = params->{sensorunit_installdate};
	my $sensorunit_lastconnect = params->{sensorunit_lastconnect};
	my $sensorunit_location = params->{sensorunit_location};
	my $sensorunit_note = params->{sensorunit_note};
	my $sensorunit_position = params->{sensorunit_position};
	my $sensorunit_status = params->{sensorunit_status};
	my $block = params->{block};
	
	my $db_setvalues='';
	if (defined $dbname){$db_setvalues.="dbname='$dbname',"}
	if (defined $product_id_ref){$db_setvalues.="product_id_ref=$product_id_ref,"}
	if (defined $customer_id_ref){$db_setvalues.="customer_id_ref=$customer_id_ref,"}
	if (defined $helpdesk_id_ref){$db_setvalues.="helpdesk_id_ref=$helpdesk_id_ref,"}
	if (defined $sensorunit_installdate){$db_setvalues.="sensorunit_installdate=$sensorunit_installdate,"}
	if (defined $sensorunit_lastconnect){$db_setvalues.="sensorunit_lastconnect=$sensorunit_lastconnect,"}
	if (defined $sensorunit_location){$db_setvalues.="sensorunit_location='$sensorunit_location',"}
	if (defined $sensorunit_note){$db_setvalues.="sensorunit_note='$sensorunit_note',"}
	if (defined $sensorunit_position){$db_setvalues.="sensorunit_position='$sensorunit_position',"}
	if (defined $sensorunit_status){$db_setvalues.="sensorunit_status=$sensorunit_status,"}
	if (defined $block){$db_setvalues.="block=$block,"}
	
	if ($db_setvalues eq ''){
		send_error("Missing parameter: needs at least one: dbname, product_id_ref, customer_id_ref, helpdesk_id_ref, sensorunit_installdate,sensorunit_lastconnect,sensorunit_location,sensorunit_note,sensorunit_position,sensorunit_status",400);
	}
	# remove last char ',' in string
	chop($db_setvalues);
	
	add2log(4,"Updating sensorunits for serialnumber:$serialnumber with db_setvalues:$db_setvalues");# Info
	my $sth = $mainbase_db_ctl->prepare("UPDATE sensorunits set $db_setvalues where serialnumber='$serialnumber'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found ssend error
	if ($result eq "0E0"){
		add2log(2,"Missing record for serialnumber:$serialnumber.");# Info
		send_error("Missing record for serialnumber:$serialnumber",404);
	}
	return {result=>"OK"};
};
del '/v1/sensorunits/delete' => sub {
	if (not params->{serialnumber} and not defined params->{sensorunit_id}){ 
		send_error("Missing parameter: needs serialnumber or senorsunit_id",400);
	}
	my $serialnumber = params->{serialnumber};
	my $sensorunit_id = params->{sensorunit_id};
	my $db_where='';
	if (defined $sensorunit_id){$db_where="sensorunit_id=$sensorunit_id"}
	if (defined $serialnumber){$db_where=" and serialnumber=$serialnumber"}

	add2log(4,"Deleting record for serialnumber:$serialnumber.");# Info
	my $sth = $mainbase_db_ctl->prepare("DELETE from sensorunits where $db_where");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found send error else send OK
	if ($result eq "0E0"){
		send_error("No record for for serialnumber:$serialnumber or sensorunit_id:$sensorunit_id. $DBI::errstr",404);
	}else{
		return{ message =>"OK"};
	}
};



get '/v1/sensorunits/units/list' => sub {
	my $limit = params->{limit};
	my $offset = params->{offset};
	my $user_id = params->{user_id};
	my $sortfield = params->{sortfield};
	my $order_by="";
	if ($sortfield){$order_by="ORDER BY $sortfield"}
	my $where="";
	if ($user_id){$where="where sensoraccess.user_id=$user_id"};

	# use view to get all data in one 
	my $sth;
	my @dataset=();

	$sth = $mainbase_db_ctl->prepare
	("select DISTINCT ON (unittypes.unittype_description) * from sensoraccess
	inner join products on substring(sensoraccess.serialnumber from 1 for 10) = substring(products.productnumber from 1 for 10)
	inner join sensorprobes on product_id_ref=product_id
	inner join unittypes on sensorprobes.sensorprobes_number = unittypes.unittype_id 
		$where $order_by
");
	
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") queue records URL /v1/sensorunits/units/list");# debug
	return{ 'result'=>\@dataset};

};

get '/v1/sensorunits/data' => sub {
	if (not params->{serialnumber} ){
		send_error("Missing parameter, needs serialnumber",400);
	}
	my $serialnumber = params->{serialnumber};
	# Check if token hass access to serialnumber
	if (not access_via_token($serialnumber)){
		send_error("No access to serialnumber:$serialnumber",403)
	}
	my $limit = params->{limit} || $default_limit;
	my $offset = params->{offset} || $default_offset;
	my $unittype = params->{unittype};
	my $probenumber = params->{probenumber};
	my $timestart = params->{timestart};
	my $timestop = params->{timestop} || 'now()';
	my $days = params->{days};
	my $sortfield = params->{sortfield};
	my $timezone = params->{timezone} || '+01';
	
	my $order_by="";
	if ($sortfield){$order_by="ORDER BY $sortfield"}
	my $where="where serialnumber='$serialnumber'";
	if (defined $probenumber){$where.="and probenumber=$probenumber"}
	if ($days){$where.=" and timestamp >= now() - interval '$days days'"}
	if ($timestart){$where.="AND timestamp BETWEEN '$timestart' AND '$timestop'"}
	
	# If unit type is used get probenumber(s) for this unittype 
	if (defined($unittype) and $unittype ne ''){
		# Get probenumber(s) for this units
		my $sth = $mainbase_db_ctl->prepare("SELECT sensorprobes_number from sensorprobes inner join products on product_id_ref=product_id where substring('$serialnumber' from 1 for 10)=productnumber and unittype_id_ref=$unittype");
		$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
		my $rows=$sth->fetchall_arrayref;
		$sth->finish();
		add2log(4,"Fetched units(".scalar(@$rows).") queue records URL /v1/sensorunits/data");# debug
		if (scalar(@$rows)){
			$where.=" and (";
			my $probe_number=0;
			foreach my $row(@$rows){
				$where.="probenumber=@$row[0] or "
			}
			$where=substr($where,0,-4).")";
		}
	}
	
	#add2log(4,"where: $where");# debug
	# use view to get all data in one 
	my $sth;
	# Get database for sensor
	$sth = $mainbase_db_ctl->prepare("SELECT dbname from sensorunits where serialnumber='$serialnumber'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my @dataset=$sth->fetchrow_array();
	$sth->finish();
	# check if we found DB
	if ($result eq "0E0"){
		send_error("Did not found customer DB for serialnumber:$serialnumber",400);
	}
	
	my $sensor_db=trim($dataset[0]);
	add2log(4,"sensor db: $sensor_db");# debug
	#return{ 'result'=>\@dataset};
	my $sensordata_db="dbi:Pg:dbname=$sensor_db;host=localhost;port=5432";
	my $sensordata_db_ctl = DBI->connect($sensordata_db, $dbuserid, $dbpasswd, { RaiseError => 1 }) 
                      or die $DBI::errstr; 
	$sth = $sensordata_db_ctl->prepare("SELECT probenumber,sequencenumber,value,timestamp,extract(epoch from timestamp at time zone '$timezone') as epoch  from sensordata $where $order_by LIMIT $limit");
	$result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";

	
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	# Remove database name from set
	shift @dataset;
	add2log(4,"Fetched (".scalar(@dataset).") queue records. URL /v1/sensorunits/data ");# debug
	return{ 'result'=>\@dataset};

};

get '/v1/sensorunits/data/latest' => sub {
	if (not params->{serialnumber} ){
		send_error("Missing parameter, needs serialnumber",400);
	}
	my $serialnumber = params->{serialnumber};
	# Check if token hass access to serialnumber
	if (not access_via_token($serialnumber)){
		send_error("No access to serialnumber:$serialnumber,403")
	}

	my $limit = params->{limit} || $default_limit;
	my $offset = params->{offset} || $default_offset;
	my $unittype = params->{unittype};
	my $probenumber = params->{probenumber};
	my $sortfield = params->{sortfield};
	my $order_by="";
	if ($sortfield){$order_by="ORDER BY $sortfield"}

	#
	my $db_where="where serialnumber='$serialnumber'";
	if (defined $probenumber){$db_where.="and probenumber=$probenumber"}
	
	# If unit type is used get probenumber(s) for this unittype 
	if (defined $unittype and $unittype ne ''){
		# Get probenumber(s) for this units
		my $sth = $mainbase_db_ctl->prepare("SELECT sensorprobes_number from sensorprobes inner join products on product_id_ref=product_id where substring('$serialnumber' from 1 for 10)=productnumber and unittype_id_ref=$unittype");
		$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
		my $rows=$sth->fetchall_arrayref;
		$sth->finish();
		add2log(4,"Fetched units(".scalar(@$rows).") queue records URL /v1/sensorunits/data/latest");# debug
		if (scalar(@$rows)){
			$db_where.=" and (";
			my $probe_number=0;
			foreach my $row(@$rows){
				$db_where.="probenumber=@$row[0] or "
			}
			$db_where=substr($db_where,0,-4).")";
		}
	}
	
	my $sth = $mainbase_db_ctl->prepare("SELECT probenumber,value,timestamp from sensorslatestvalues $db_where $order_by");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";

	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") queue records URL /v1/sensorunits/data/latest");# debug
	return{ 'result'=>\@dataset};

};

get '/v1/sensorunits/variable/get' => sub {
	if (!authorized('/v1/command',params->{serialnumber})){
		send_error("You are not authorized to access this record",401);
	}

	my $db_where=' where';
  # Build SQL string
	if (defined params->{serialnumber}){
		my $serialnumber=params->{serialnumber};
		$db_where.=" serialnumber='$serialnumber'";
	}
	if (defined params->{productnumber}){
		my $productnumber=params->{productnumber};
		$db_where.=" serialnumber like '$productnumber%'";
	}
	if (defined params->{variable}){
		my $variable=params->{variable};
		$db_where.=" and variable='$variable'";
	}
	
	# make query
	my $sth = $mainbase_db_ctl->prepare("SELECT serialnumber,variable,value,dateupdated FROM sensorunit_variables $db_where");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") queue records. With db_where:$db_where URL /v1/sensorunits/variable/get");# debug
	return{ 'result'=>\@dataset};
};
#
post '/v1/sensorunits/variable/add' => sub {
	if (not params->{serialnumber} or not defined params->{variable} ){
		send_error("Missing parameter: needs serialnumber and variable",400);
	}
	if (!authorized('/v1/command',params->{serialnumber})){
		send_error("You are not authorized to access this record",401);
	}
	my $serialnumber=params->{serialnumber};
	my $variable=params->{variable};
	my $value=params->{value} || '0';

	# test if record already exists
	my $sth = $mainbase_db_ctl->prepare("SELECT serialnumber FROM sensorunit_variables WHERE serialnumber='$serialnumber' and variable='$variable'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	if ($result ne "0E0"){
		add2log(2,"Record exists for serialnumber:$serialnumber and variable:$variable.");# Info
		send_error("Record exists for serialnumber:$serialnumber and variable:$variable",302);
	}
	
	$sth = $mainbase_db_ctl->prepare("INSERT into sensorunit_variables (serialnumber,variable,value,dateupdated) values ('$serialnumber','$variable','$value',current_timestamp)");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	return {result=>"OK"};
};
#
patch '/v1/sensorunits/variable/update' => sub {
	if (not defined params->{serialnumber} or not defined params->{variable} ){
		send_error("Missing parameter: needs serialnumber and variable",400);
	}
	if (!authorized('/v1/command',params->{serialnumber})){
		send_error("You are not authorized to access this record",401);
	}
	my $serialnumber=params->{serialnumber};
	my $variable=params->{variable};
	my $value=params->{value}; if ($value eq ''){$value='0'}
	my $sth;
	# Get currect time in Postgres format
	# my $dateupdated=localtime()->strftime('%F %T');
	$sth = $mainbase_db_ctl->prepare("UPDATE sensorunit_variables set value='$value', dateupdated=current_timestamp where serialnumber='$serialnumber' and variable='$variable'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	#print "result:$result\n";
	if ($result eq "0E0"){
		#"INSERT INTO config (serialnumber,variable,value,dateupdated,queueid,statusid) VALUES
		$sth = $mainbase_db_ctl->prepare( "INSERT INTO sensorunit_variables (serialnumber,variable,value,dateupdated) VALUES ('$serialnumber','$variable','$value',current_timestamp)");
		$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
		add2log(2,"$serialnumber: Missing variable: $variable  for serialnumber: $serialnumber. Created");# Info
	}
	# Add command to queue
	#add_config2queue($serialnumber,$variable,$value);
	return {result=>"OK"};
};
##

del '/v1/sensorunits/variable/delete' => sub {
	if (not params->{serialnumber}){
		send_error("Missing parameter: needs serialnumber",400);
	}
	my $serialnumber = params->{serialnumber};
	my $variable=params->{variable};
	
	my $db_where='';
	if (defined $serialnumber){$db_where="serialnumber='$serialnumber'"}
	if (defined $variable){$db_where.=" and variable='$variable'"}
		
	my $sth = $mainbase_db_ctl->prepare("DELETE from sensorunit_variables where $db_where");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found send error else send OK
	if ($result eq "0E0"){
	send_error("No record for serialnumber:$serialnumber. $DBI::errstr",404);
	}else{
		#add2log(4,"Delete record document: '$document_id' '$rv'");# Info
	return{ result =>"OK"};
	}
};






######################################################################
#
# API for sensorprobes
#
# List probes per productnumber, filter on product_id_ref or unittype

get '/v1/sensorprobes/list' => sub {
	my $limit = params->{limit} || '';
	my $offset = params->{offset} || '';
	my $productnumber = params->{productnumber};
	my $unittype = params->{unittype};
	my $sortfield = params->{sortfield} || '';
	my $product_id_ref = params->{product_id_ref};
	my $sensorprobes_alert_hidden = params->{sensorprobes_alert_hidden};
	
	my $order_by="";
	if ($sortfield){$order_by="ORDER BY $sortfield"}
	my $db_where="";
	if ($productnumber){
		$db_where="WHERE public.products.productnumber = '$productnumber'";
		if (defined $unittype){$db_where.=" and public.unittypes.unittype_id = $unittype"};
		if (defined $product_id_ref){$db_where.=" and public.sensorprobes.product_id_ref = $product_id_ref"};
	}
	if (not $productnumber and defined $unittype){
		$db_where="WHERE public.unittypes.unittype_id = $unittype";
		if (defined $product_id_ref){$db_where.=" and public.sensorprobes.product_id_ref = $product_id_ref"};
	}
	if (not $productnumber and not defined $unittype and defined $product_id_ref){
		$db_where="WHERE public.sensorprobes.product_id_ref = $product_id_ref";
	}
	#add2log(4,"Listing records with parameters product_id_ref:$product_id_ref, unittype:$unittype, productnumber:$productnumber.");# Info
	my $sth = $mainbase_db_ctl->prepare("SELECT
  public.products.productnumber, product_id_ref, public.sensorprobes.hidden, public.sensorprobes.sensorprobes_number, sensorprobes_alert_hidden,
  public.unittypes.unittype_id, public.unittypes.unittype_description, public.unittypes.unittype_shortlabel, public.unittypes.unittype_url, public.unittypes.unittype_label, public.unittypes.unittype_decimals
	FROM public.sensorprobes
	INNER JOIN public.unittypes	ON (public.sensorprobes.unittype_id_ref = public.unittypes.unittype_id)
	INNER JOIN products ON product_id_ref = product_id
	$db_where $order_by");
	
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") queue records URL /v1/sensorprobes/list");# debug
	return{ 'result'=>\@dataset};
};

patch '/v1/sensorprobes/update' => sub {
	if (not defined params->{product_id_ref} or not defined params->{sensorprobes_number} or not defined params->{unittype_id_ref}){
		
		send_error("Missing parameter: needs product_id_ref, sensorprobes_number and unittype_id_ref",400);
	}
	my $product_id_ref = params->{product_id_ref};
	my $sensorprobes_number = params->{sensorprobes_number};
	my $unittype_id_ref = params->{unittype_id_ref};
	my $sensorprobes_url = params->{sensorprobes_url};
	my $sensorprobes_alert_hidden = params->{sensorprobes_alert_hidden};
	
	my $db_setvalues='';
	if (defined $unittype_id_ref){$db_setvalues.="unittype_id_ref=$unittype_id_ref,"}
	if (defined $sensorprobes_url){$db_setvalues.="sensorprobes_url='$sensorprobes_url',"}
	if (defined $sensorprobes_alert_hidden){$db_setvalues.="sensorprobes_url='$sensorprobes_alert_hidden',"}

	# remove last char ',' in string
	chop($db_setvalues);
	add2log(3,"Updating sensorprobes with: $db_setvalues for product_id_ref=$product_id_ref and sensorprobes_number=$sensorprobes_number");
	
	my $sth;
	$sth = $mainbase_db_ctl->prepare("UPDATE sensorprobes set $db_setvalues where product_id_ref='$product_id_ref' and sensorprobes_number=$sensorprobes_number");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found create record
	if ($result eq "0E0"){
		$sth = $mainbase_db_ctl->prepare( "INSERT INTO sensorprobes (product_id_ref,sensorprobes_number,unittype_id_ref) VALUES ('$product_id_ref',$sensorprobes_number,$unittype_id_ref)");
		$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
		add2log(2,"Missing unittype_id_ref:$unittype_id_ref for product_id_ref:$product_id_ref and sensorprobes_number:$sensorprobes_number. Created");# Info
	}
	return {result=>"OK"};
};

del '/v1/sensorprobes/delete' => sub {
	if (not params->{product_id_ref} and not params->{sensorprobes_number}){
		send_error("Missing parameter: needs product_id_ref or (product_id_ref and sensorprobes_number)",400);
	}
	my $product_id_ref = params->{product_id_ref};
	my $sensorprobes_number = params->{sensorprobes_number};
	my $db_where='';
	if (defined $product_id_ref){$db_where="product_id_ref=$product_id_ref"}
	if (defined $sensorprobes_number){$db_where=" and sensorprobes_number=$sensorprobes_number"}
	
	my $sth = $mainbase_db_ctl->prepare("DELETE from sensorprobes where $db_where");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found send error else send OK
	if ($result eq "0E0"){
		send_error("No record for product_id_ref:$product_id_ref, sensorprobes_number:$sensorprobes_number. $DBI::errstr",404);
  	}else{
  	#add2log(4,"Delete record document: '$document_id' '$rv'");# Info
   	return{ message =>"OK"};
	}
};
get '/v1/sensorprobes/variable/list' => sub {
	my $limit = params->{limit};
	my $offset = params->{offset};
	my $serialnumber = params->{serialnumber};
	my $sensorprobe_number = params->{sensorprobe_number};
	my $variable = params->{variable};
	my $sortfield = params->{sortfield};

	my $db_order_by='';
	if ($sortfield){$db_order_by="ORDER BY $sortfield"}
	my $db_where='';
	if ($serialnumber){$db_where="WHERE serialnumber = '$serialnumber'"};
	if ($sensorprobe_number){$db_where="AND sensorprobe_number = $sensorprobe_number"};
	if (defined $variable){$db_where.=" AND variable = '$variable'"};
	
	my $db_limit='';
	my $db_offset='';
	if ($limit){$db_limit="LIMIT $limit"}
	if ($offset){$db_offset="OFFSET $offset"}

	my $sth = $mainbase_db_ctl->prepare("SELECT serialnumber,sensorprobe_number,variable,value,dateupdated FROM sensorprobe_variables $db_where $db_order_by  $db_limit $db_offset");
	
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") customer variables records");# debug
	return{ 'result'=>\@dataset};
};

patch '/v1/sensorprobes/variable/update' => sub {
	if (not params->{serialnumber} or not params->{variable} or not defined params->{value} or not defined params->{sensorprobe_number}){
		send_error("Missing parameter: needs serialnumber, sensorprobe_number, variable and value",400);
	}
	my $serialnumber = params->{serialnumber};
	my $sensorprobe_number = params->{sensorprobe_number};
	my $variable = params->{variable};
	my $value = params->{value};

	my $db_setvalues="value='$value'";
	
	my $sth = $mainbase_db_ctl->prepare("UPDATE sensorprobe_variables set $db_setvalues,dateupdated=current_timestamp where serialnumber='$serialnumber' and sensorprobe_number=$sensorprobe_number and variable='$variable'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found create record
	if ($result eq "0E0"){
		$sth = $mainbase_db_ctl->prepare( "INSERT INTO sensorprobe_variables (serialnumber,sensorprobe_number,variable,value,dateupdated) VALUES ('$serialnumber',$sensorprobe_number,'$variable','$value',current_timestamp)");
		$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
		add2log(2,"Missing record for serialnumber:$serialnumber, sensorprobe_number:$sensorprobe_number and variable:$variable. Created");# Info
	}
	return {result=>"OK"};
};
del '/v1/sensorprobes/variable/delete' => sub {
	if (not params->{serialnumber} or not params->{sensorprobe_number} or not params->{variable}){
		send_error("Missing parameter: needs productnumber,sensorprobe_number and variable",400);
	}
	my $serialnumber = params->{serialnumber};
	my $sensorprobe_number = params->{sensorprobe_number};
	my $variable = params->{variable};
	
	my $sth = $mainbase_db_ctl->prepare("DELETE from sensorprobe_variables where serialnumber='$serialnumber' and sensorprobe_number=$sensorprobe_number and variable='$variable'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found send error else send OK
	if ($result eq "0E0"){
		send_error("No record for serialnumber:$serialnumber, and sensorprobe_number:$sensorprobe_number variable:$variable.",404);
  	}else{
   	return{ message =>"OK"};
	}
};


#########################################################
#
# Document API
#
get '/v1/document/list' => sub {
	
	my $limit = params->{limit};
	my $page = params->{page};
	my $serialnumber = params->{serialnumber};
	my $language = params->{language};
	my $sortfield = params->{sortfield};
	my $order_by="";
	if ($sortfield){$order_by="ORDER BY $sortfield"}
	my $db_where='';
	if ($language and !$serialnumber){$db_where="where language='$language'"}
	if (!$language and $serialnumber){$db_where="where serialnumber='$serialnumber'"}
	if ($language and $serialnumber){$db_where="where serialnumber='$serialnumber' and language='$language'"}
	add2log(4,"/v1/documents/list db_where:$db_where");# debug
	
	my @dataset=();
	my $sth = $mainbase_db_ctl->prepare("SELECT document_id,document_name,document_url,document_language,document_version,document_regdate,document_updated  FROM documents $db_where $order_by");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") queue records URL /v1/document/list");# debug
	return{ 'result'=>\@dataset};
};
#
post '/v1/document/add' => sub {
	if (not defined params->{document_name} or not params->{document_url}) {
		send_error("Missing parameter: needs document_name and document_url",400);
	}
	my $document_name = params->{document_name};
	my $document_url = params->{document_url};
	my $document_language = params->{document_language} || '';
	my $document_version = params->{document_version} || '';

	my $sth = $mainbase_db_ctl->prepare("INSERT INTO documents (document_name,document_url,document_language,document_version,document_regdate,document_updated) VALUES ($document_name,$document_url,$document_language,$document_version,currenttime,currenttime");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	add2log(4,"Added record into documents: '$document_name', '$document_url'");# Info
	return{result =>"OK"};
};
#	

del '/v1/document/delete' => sub {
	if (not defined params->{document_id}) {
		send_error("Missing parameter: needs document_id",400);
	}
	my $document_id=params->{user_id};
	# Delete firmware from database $sth = $dbportalctl->prepare(
	
	my $sth = $mainbase_db_ctl->prepare("DELETE from documents where document_id=$document_id");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	
	if( $sth->rows < 1 ){
		send_error("No document id for for id:$document_id. $DBI::errstr",404);
  	}else{
  	#add2log(4,"Delete record document: '$document_id' '$rv'");# Info
   	return{ message =>"OK"};
	}
};

#################################################
#
# Irrigation API
#
get '/v1/irrigation/runlog/list' => sub {
	if (not params->{serialnumber} ){
		send_error("Missing parameter, needs serialnumber",400);
	}
	my $limit = params->{limit} || $default_limit;
	my $offset = params->{offset} || $default_offset;
	my $serialnumber = params->{serialnumber};
	my $sortfield = params->{sortfield};
	my $order_by="";
	my $db_offset='';
	my $db_limit='';
	my $db_where="WHERE serialnumber='$serialnumber'";
	if ($sortfield){$order_by="ORDER BY $sortfield"}
	if ($limit){$db_limit="LIMIT $limit"}
	if ($offset){$db_offset="OFFSET $offset"}
	
	my $sth = $mainbase_db_ctl->prepare("SELECT serialnumber,irrigation_starttime,irrigation_endtime,irrigation_startpoint,irrigation_endpoint,irrigation_nozzlewidth,irrigation_nozzlebar,irrigation_run_id,irrigation_note,hidden,irrigation_nozzleadjustment,portal_endpoint from irrigation_log $db_where $order_by $db_limit $db_offset");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";

	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") queue records URL /v1/irrigation/runlog/list");# debug
	return{ 'result'=>\@dataset};
};
patch '/v1/irrigation/runlog/update' => sub {
	if (not params->{serialnumber} or not params->{irrigation_run_id} or (not params->{hidden} and not params->{portal_endpoint})){
		send_error("Missing parameter, needs serialnumber, irrigation_run_id and (hidden or portal_endpoint)",400);
	}
	my $irrigation_run_id = params->{irrigation_run_id};
	my $hidden = params->{hidden};
	my $serialnumber = params->{serialnumber};
	my $portal_endpoint = params->{portal_endpoint};
	
	my $db_setvalues='';
	if ($hidden){$db_setvalues.="hidden='$hidden',"}
	if ($portal_endpoint){$db_setvalues.="portal_endpoint='$portal_endpoint',"}
	# remove last char in string
	chop($db_setvalues);
	

	my $sth = $mainbase_db_ctl->prepare("UPDATE irrigation_log set $db_setvalues where serialnumber='$serialnumber' and irrigation_run_id=$irrigation_run_id");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";

	if ($result eq "0E0"){
		send_error("Record for serialnumber:$serialnumber, irrigation_run_id:$irrigation_run_id do not exists",404);
	}
	return {result=>"OK"};
};

################################################
#
# Products API
#
get '/v1/products/list' => sub {
	my $limit = params->{limit};
	my $offset = params->{offset};
	my $productnumber = params->{productnumber};
	my $sensortype = params->{sensortype};
	my $product_id = params->{product_id};
	
	my $where="";
	if (defined $productnumber){$where="where productnumber='$productnumber'"}
	if (defined $product_id){$where="where product_id='$product_id'"}
	my $sortfield = params->{sortfield};
	my $order_by="";
	if ($sortfield){$order_by="ORDER BY $sortfield"}

	# use view to get all data in one 
	my $sth;
	my @dataset=();
	$sth = $mainbase_db_ctl->prepare("SELECT product_id,productnumber, product_name, product_description,product_type,product_image_url,document_id_ref from products  $where $order_by");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") queue records URL /v1/products/list");# debug
	return{ 'result'=>\@dataset};
};

patch '/v1/products/update' => sub {
    if (not params->{productnumber}){
        send_error("Missing parameter: needs productnumber",400);
    }
    my $productnumber = params->{productnumber};
    my $product_name = params->{product_name} || '';
    my $product_description = params->{product_description} || '';
    my $product_type = params->{product_type} || '1';
    my $product_image_url = params->{product_image_url} || '';
    my $document_id_ref = params->{document_id_ref};
    my $db_setvalues='';
    if ($product_name){$db_setvalues.="product_name='$product_name',"}
    if ($product_description){$db_setvalues.="product_description='$product_description',"}
    if ($product_type){$db_setvalues.="product_type=$product_type,"}
    if ($product_image_url){$db_setvalues.="product_image_url='$product_image_url',"}
    if ($document_id_ref){$db_setvalues.="document_id_ref='$document_id_ref',"}
    # remove last char in string
    chop($db_setvalues);
    
    my $sth;
    $sth = $mainbase_db_ctl->prepare("UPDATE products set $db_setvalues where productnumber='$productnumber'");
    my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
    # If not found create record
    if ($result eq "0E0"){
        $sth = $mainbase_db_ctl->prepare( "INSERT INTO products (productnumber,product_name,product_description,product_type,product_image_url,document_id_ref) VALUES ('$productnumber','$product_name','$product_description',$product_type,'$product_image_url',$document_id_ref)");
        $sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
        add2log(2,"Missing product:$productnumber. Created");# Info
    }
    return {result=>"OK"};
};




del '/v1/products/delete' => sub {
	if (not defined params->{productnumber} and not defined params->{product_id}) {
		send_error("Missing parameter: needs productnumber or product_id",400);
	}
	my $productnumber = params->{productnumber};
	my $product_id = params->{product_id};
	
	my $db_where="";
	if (defined $productnumber){$db_where="where productnumber='$productnumber'"}
	if (defined $product_id){$db_where="where product_id=$product_id"}
	
	my $sth = $mainbase_db_ctl->prepare("DELETE from products $db_where");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found send error else send OK
	if ($result eq "0E0"){
		send_error("No record for for productnumber:$productnumber or product_id:$product_id. $DBI::errstr",404);
  	}else{
   	return{ message =>"OK"};
	}
};

get '/v1/products/type/list' => sub {
	my $limit = params->{limit};
	my $offset = params->{offset};
	my $product_type_id = params->{products_type_id} || '';
	my $sortfield = params->{sortfield};

	my $db_where='';
	if ($product_type_id){$db_where="WHERE product_type_id = '$product_type_id'"};
	my $db_order_by='';
	my $db_limit='';
	my $db_offset='';
	if ($sortfield){$db_order_by="ORDER BY $sortfield"} # if defined it should not be 0 or empty
	if (defined $limit){$db_limit="LIMIT $limit"} # if defined it should not be 0 or empty
	if (defined $offset){$db_offset="OFFSET $offset"} # if defined it should not be 0 or empty
	
	add2log(4,"Listing records with parameters product_type_id:$product_type_id");# Info
	my $sth = $mainbase_db_ctl->prepare("SELECT product_type_id, product_type_name, product_type_description	FROM products_type	$db_where $db_order_by  $db_limit $db_offset");
	
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") queue records URL /v1/products/type/list");# debug
	return{ 'result'=>\@dataset};
};
post '/v1/products/type/add' => sub {
	if (not defined params->{product_type_name}){
		send_error("Missing parameter: needs products_type_name",400);
	}
	my $product_type_name = params->{product_type_name};
	my $product_type_description = params->{product_type_description};
	

	add2log(4,"Adding record for product_type_name:$product_type_name, product_type_description:$product_type_description.");# Info
	my $sth = $mainbase_db_ctl->prepare( "INSERT INTO products_type (product_type_name,product_type_description) VALUES ('$product_type_name','$product_type_description')");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	return {result=>"OK"};
};

patch '/v1/products/type/update' => sub {
	if (not defined params->{product_type_id}){
		send_error("Missing parameter: needs products_type_id",400);
	}
	my $product_type_id = params->{product_type_id};
	my $product_type_name = params->{product_type_name};
	my $product_type_description = params->{product_type_description};

	my $db_setvalues='';
	if (defined $product_type_name){$db_setvalues.="product_type_name='$product_type_name',"}
	if (defined $product_type_description){$db_setvalues.="product_type_description='$product_type_description',"}
	# remove last char ',' in string
	chop($db_setvalues);
	
	add2log(4,"Updating record for product_type_id:$product_type_id with product_type_name:$product_type_name, product_type_description:$product_type_description.");# Info
	my $sth = $mainbase_db_ctl->prepare("UPDATE products_type set $db_setvalues where product_type_id=$product_type_id");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found create record
	if ($result eq "0E0"){
		$sth = $mainbase_db_ctl->prepare( "INSERT INTO products_type (product_type_name,product_type_description) VALUES ('$product_type_name','$product_type_description')");
		$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
		add2log(2,"Missing record for product_type_id:$product_type_id. Created");# Info
	}
	return {result=>"OK"};
};
del '/v1/products/type/delete' => sub {
	if (not defined params->{product_type_id}){
		send_error("Missing parameter: needs product_type_id",400);
	}
	my $product_type_id = params->{product_type_id};
	
	add2log(4,"Deleting record for product_type_id:$product_type_id.");# Info
	my $sth = $mainbase_db_ctl->prepare("DELETE from products_type where product_type_id=$product_type_id");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found send error else send OK
	if ($result eq "0E0"){
		send_error("No record for product_type_id:$product_type_id. $DBI::errstr",404);
  	}else{
   	return{ message =>"OK"};
	}
};

get '/v1/products/sensorunits/list' => sub {
	if (!authorized('/v1/',params->{serialnumber})){
		send_error("You are not authorized to access this record",401);
	}
	my $db_where='';
	# Build SQL string
	if (defined params->{productnumber}){
		my $productnumber=params->{productnumber};
		$db_where.=" where substring(serialnumber from 1 for 10)='$productnumber'";
	}
	# make query
	my $sth = $mainbase_db_ctl->prepare("SELECT serialnumber FROM sensorunits $db_where");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") sensorunits-firmware records. With db_where:$db_where");# debug
	return{ 'result'=>\@dataset};
};





################################################
#
# User handling
#
get '/v1/user/list' => sub {
	my $limit = params->{limit};
	my $page = params->{page};
	my $user_email = params->{user_email};
	my $user_id = params->{user_id};
	my $sortfield = params->{sortfield};
	my $order_by="";
	if ($sortfield){$order_by="ORDER BY $sortfield"}

	my $sth;
	my @dataset=();
	if ($user_email){
		$sth = $mainbase_db_ctl->prepare("SELECT user_id,user_name,users.customernumber,user_phone_work,user_email,user_password,user_language,customer.customer_name,customertype.customertype,roletype.roletype_id,roletype.roletype from users inner join customer on users.customer_id_ref=customer.customer_id inner join customertype on customer.customertype_id_ref=customertype.customertype_id inner join roletype on users.roletype_id_ref=roletype.roletype_id where user_email='$user_email' $order_by");
	}
	if ($user_id){
		$sth = $mainbase_db_ctl->prepare("SELECT user_id,user_name,users.customernumber,user_phone_work,user_email,user_password,user_language,customer.customer_name,customertype.customertype,roletype.roletype_id,roletype.roletype from users inner join customer on users.customer_id_ref=customer.customer_id inner join customertype on customer.customertype_id_ref=customertype.customertype_id inner join roletype on users.roletype_id_ref=roletype.roletype_id where user_id='$user_id' $order_by");
	}
	if (not $user_id and  not $user_email){
		$sth = $mainbase_db_ctl->prepare("SELECT user_id,user_name,users.customernumber,user_phone_work,user_email,user_password,user_language,customer.customer_name,customertype.customertype,roletype.roletype_id,roletype.roletype from users inner join customer on users.customer_id_ref=customer.customer_id inner join customertype on customer.customertype_id_ref=customertype.customertype_id inner join roletype on users.roletype_id_ref=roletype.roletype_id $order_by");
	}
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") queue records URL /v1/user/list");# debug
	return{ 'result'=>\@dataset};
};
#
post '/v1/user/add' => sub {
	my $user_email = params->{user_email};
	my $user_password = params->{user_password} || '';
	my $user_name = params->{user_name} || '';
	my $sth;
	# check if record alredy exists
	$sth = $mainbase_db_ctl->prepare("SELECT user_id from users WHERE user_email='$user_email'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	if ($result ne "0E0"){
		send_error("Users email already exists",302);
	}
	my $db_fields="";
	my $db_values="";
	if ($user_name){$db_fields.=",user_name";$db_values.=",'$user_name'"}
	add2log(4,"$db_fields;$db_values");
		
	my $SQL = "INSERT INTO users (user_email,user_password$db_fields) VALUES ('$user_email','$user_password'$db_values)";
	$sth = $mainbase_db_ctl->do($SQL); 
	add2log(4,"Added record into users: '$user_email,'$user_password'");# Info
	return{result =>"OK"};
};
#	
patch '/v1/user/update' => sub {
	if (not params->{user_id} and not params->{user_email} ){
		send_error("Missing parameter, needs user_id or user_email",400);
	}
	my $user_id=params->{user_id};
	my $user_email=params->{user_email};
	my $db_where='';
	if ($user_id){$db_where.="user_id=$user_id"}
	if ($user_email and !$user_id){$db_where.="user_email='$user_email'"}
	
	my $updatelist='';
	if (params->{user_name}){$updatelist.="user_name='".params->{user_name}."',"};
	if (params->{user_phone_work}){$updatelist.="user_phone_work='".params->{user_phone_work}."',"};
	if (params->{user_password}){$updatelist.="user_password='".params->{user_password}."',"};
	if (params->{user_roletype_id}){$updatelist.="user_roletype_id='".params->{user_roletype_id}."',"};
	# If user-id is used, the email can be changed
	if ($user_id and params->{user_email}){$updatelist.="user_email='".params->{user_email}."',"};
	if (params->{user_language}){$updatelist.="user_language='".params->{user_language}."',"};
	# remove last char
	chop($updatelist);
	
	my $sth;
	add2log(4,"Changed user:$updatelist");# Info
	$sth = $mainbase_db_ctl->prepare( "UPDATE users set $updatelist where $db_where");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	
	if($sth->rows < 1) {
		send_error("Did not find record with oid $oid",404);
	}else{
		return {result=>"OK"};
	}
};

del '/v1/user/delete' => sub {
	if (not params->{user_id}) {
		send_error("Missing parameter: needs oid",400);
	}
	my $user_id=params->{user_id};
	# Delete firmware from database $sth = $dbportalctl->prepare(
	
	my $sth = $mainbase_db_ctl->prepare("DELETE from userssensor where user_id=$user_id");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	
	if( $sth->rows < 1 ){
		#add2log(4,"Delete record firmware: '$oid' '$rv'");# Info
		send_error("No userid for for id:$user_id. $DBI::errstr",404);
  	}else{
  	#add2log(4,"Delete record firmware: '$oid' '$rv'");# Info
   	return{ message =>"OK"};
	}
};
get '/v1/user/variable/get' => sub {
#	if (!authorized('/v1/command',params->{serialnumber})){
#		send_error("You are not authorized to access this record",401);
#	}
	
	my $user_id=params->{user_id} || '';
	my $variable=params->{variable} || '';
	my $db_where=' where';
	# If not user_id or variable show all variables
	if (not $user_id and not $variable){$db_where=''}
  # Build SQL string
	if ($user_id){$db_where.=" user_id='$user_id'"}
	if ($variable){$db_where.=" and variable='$variable'"}
	
	# make query
	my $sth = $mainbase_db_ctl->prepare("SELECT * FROM user_variables $db_where");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") queue records. With db_where:$db_where URL /v1/user/variable/get");# debug
	return{ 'result'=>\@dataset};
};
#
post '/v1/user/variable/add' => sub {
	if (not params->{user_id} or not defined params->{variable} ){
		send_error("Missing parameter: needs user_id and variable",400);
	}
#	if (!authorized('/v1/command',params->{serialnumber})){
#		send_error("You are not authorized to access this record",401);
#	}
	my $user_id=params->{user_id};
	my $variable=params->{variable};
	my $value=params->{value} || '0';

	# test if record already exists
	my $sth = $mainbase_db_ctl->prepare("SELECT user_id FROM user_variables WHERE user_id=$user_id and variable='$variable'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	if ($result ne "0E0"){
		add2log(2,"Record exists for user_id:$user_id and variable:$variable.");# Info
		send_error("Record exists for user_id:$user_id and variable:$variable",302);
	}
	
	$sth = $mainbase_db_ctl->prepare("INSERT into user_variables (user_id,variable,value,updated_at,created_at) values ($user_id,'$variable','$value',current_timestamp,current_timestamp)");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	return {result=>"OK"};
};
#
patch '/v1/user/variable/update' => sub {
	if (not defined params->{user_id} or not defined params->{variable} ){
		send_error("Missing parameter: needs user_id and variable",400);
	}
#	if (!authorized('/v1/command',params->{serialnumber})){
#		send_error("You are not authorized to access this record",401);
#	}
	my $user_id=params->{user_id};
	my $variable=params->{variable};
	my $value=params->{value}; if ($value eq ''){$value='0'}
	my $sth;
	# Get currect time in Postgres format
	# my $dateupdated=localtime()->strftime('%F %T');
	$sth = $mainbase_db_ctl->prepare("UPDATE user_variables set value='$value', updated_at=current_timestamp where user_id='$user_id' and variable='$variable'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	#print "result:$result\n";
	if ($result eq "0E0"){
		$sth = $mainbase_db_ctl->prepare( "INSERT INTO user_variables (user_id,variable,value,updated_at,created_at) VALUES ('$user_id','$variable','$value',current_timestamp,current_timestamp)");
		$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
		add2log(2,"$user_id: Missing variable: $variable  for user_id: $user_id. Created");# Info
	}
	# Add command to queue
	#add_config2queue($serialnumber,$variable,$value);
	return {result=>"OK"};
};
##

del '/v1/user/variable/delete' => sub {
	if (not params->{user_id}){
		send_error("Missing parameter: needs user_id, option variable and user_variables_id",400);
	}
	my $user_id = params->{user_id};
	my $variable=params->{variable} || '';
	my $user_variables_id=params->{user_variables_id} || 0;
	
	my $db_where='';
	if ($user_id){$db_where="user_id='$user_id'"}
	if ($variable){$db_where.=" and variable='$variable'"}
	if ($user_variables_id){$db_where.=" and user_variables_id='$user_variables_id'"}
		
	my $sth = $mainbase_db_ctl->prepare("DELETE from user_variables where $db_where");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found send error else send OK
	if ($result eq "0E0"){
	send_error("No record for user_id:$user_id. $DBI::errstr",404);
	}else{
		#add2log(4,"Delete record document: '$document_id' '$rv'");# Info
	return{ result =>"OK"};
	}
};




######################################################################
#
# API for unittypes
#

get '/v1/unittypes/list' => sub {
	my $limit = params->{limit};
	my $offset = params->{offset};
	my $unittype_id = params->{unittype_id};
	my $sortfield = params->{sortfield};
	
	my $db_order_by="";
	if ($sortfield){$db_order_by="ORDER BY $sortfield"}
	my $db_where="";
	if (defined $unittype_id){$db_where="WHERE public.unittypes.unittype_id = $unittype_id"};
	my $db_limit='';
	my $db_offset='';
	if (defined $limit){$db_limit="LIMIT $limit"}
	if (defined $offset){$db_offset="OFFSET $offset"}

	my $sth = $mainbase_db_ctl->prepare("SELECT unittype_id, unittypes.unittype_description, unittypes.unittype_shortlabel, unittypes.unittype_decimals FROM unittypes $db_where $db_order_by $db_limit $db_offset");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") queue records URL /v1/unittypes/list");# debug
	return{ 'result'=>\@dataset};
};

patch '/v1/unittypes/update' => sub {
	if (not params->{unittype_id}){
		send_error("Missing parameter: needs unittype_id",400);
	}
	my $unittype_id = params->{unittype_id};
	my $unittype_description = params->{unittype_description} || '';
	my $unittype_shortlabel	= params->{unittype_shortlabel} || '';
	my $unittype_label = params->{unittype_label} || '';
	my $unittype_decimal = params->{unittype_decimal};
	my $db_setvalues='';
	if ($unittype_description){$db_setvalues.="unittype_description='$unittype_description',"}
	if ($unittype_shortlabel){$db_setvalues.="unittype_shortlabel='$unittype_shortlabel',"}
	if ($unittype_label){$db_setvalues.="unittype_label='$unittype_label',"}
	if (defined $unittype_decimal){$db_setvalues.="unittype_decimal=$unittype_decimal,"}
	# remove last char ',' in string
	chop($db_setvalues);
	
	my $sth = $mainbase_db_ctl->prepare("UPDATE sensorprobes set $db_setvalues where unittype_id=$unittype_id");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found create record
	if ($result eq "0E0"){
		$sth = $mainbase_db_ctl->prepare( "INSERT INTO sensorprobes (unittype_description,unittype_shortlabel,unittype_label,unittype_decimal) VALUES ('$unittype_description','$unittype_shortlabel','$unittype_label',$unittype_decimal)");
		$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
		add2log(2,"Missing record for unittype_id:$unittype_id. Created");# Info
	}
	return {result=>"OK"};
};
del '/v1/unittypes/delete' => sub {
	if (not params->{unittype_id}){
		send_error("Missing parameter: needs unittype_id",400);
	}
	my $unittype_id = params->{unittype_id};
	
	my $sth = $mainbase_db_ctl->prepare("DELETE from sensorprobes where unittype_id=$unittype_id");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found send error else send OK
	if ($result eq "0E0"){
		send_error("No record for unittype_id:$unittype_id. $DBI::errstr",404);
  	}else{
   	return{ message =>"OK"};
	}
};
######################################################################
#
# API for customers
#

get '/v1/customers/list' => sub {
	my $limit = params->{limit};
	my $offset = params->{offset};
	my $customernumber = params->{customernumber};
	my $customer_id = params->{customer_id};
	my $unittype = params->{unittype};
	my $sortfield = params->{sortfield};

	my $db_where='';
	if (defined $customernumber and $customernumber ne ''){$db_where="WHERE customernumber = '$customernumber'"};
	if (defined $customer_id and $customer_id ne ''){$db_where="WHERE customer_id = $customer_id"};
	my $db_order_by='';
	my $db_limit='';
	my $db_offset='';
	if ($sortfield){$db_order_by="ORDER BY $sortfield"} # if defined it should not be 0 or empty
	if ($limit){$db_limit="LIMIT $limit"} # if defined it should not be 0 or empty
	if ($offset){$db_offset="OFFSET $offset"} # if defined it should not be 0 or empty

	add2log(4,"Listing records with parameters $db_where");# Info
	my $sth = $mainbase_db_ctl->prepare("SELECT customernumber,customer_name,customer_vatnumber,customer_phone,customer_fax,customer_email,customer_web,customer_visitaddr1,customer_visitaddr2,customer_visitpostcode,customer_visitcity,customer_visitcountry,
	customer_invoiceaddr1,customer_invoiceaddr2,customer_invoicepostcode,customer_invoicecity,customer_invoicecountry,customer_deliveraddr1,customer_deliveraddr2,customer_deliverpostcode,customer_delivercity,customer_delivercountry,
	customer_maincontact,customer_deliveraddr_same_as_invoice,customer_invoiceaddr_same_as_visit,customertype_id_ref,customer_site_title,customer_id,customertype.customertype,customertype.description
	FROM customer
	INNER JOIN customertype ON (customer.customertype_id_ref = customertype.customertype_id)
	$db_where $db_order_by  $db_limit $db_offset");
	
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") queue records URL /v1/customers/list");# debug
	return{ 'result'=>\@dataset};
};
post '/v1/customers/add' => sub {
	if (not defined params->{customernumber}){
		send_error("Missing parameter: needs customernumber",400);
	}
	my $customernumber = params->{customernumber};
	my $customer_name = params->{customer_name} || '';
	my $customer_vatnumber = params->{customer_vatnumber} || '';
	my $customer_phone = params->{customer_phone} || '';
	my $customer_fax = params->{customer_fax} || '';
	my $customer_email = params->{customer_email} || '';
	my $customer_web = params->{customer_web} || '';
	my $customer_visitaddr1 = params->{customer_visitaddr1} || '';
	my $customer_visitaddr2 = params->{customer_visitaddr2} || '';
	my $customer_visitpostcode = params->{customer_visitpostcode} || '';
	my $customer_visitcity = params->{customer_visitcity} || '';
	my $customer_visitcountry = params->{customer_visitcountry} || '0';
	my $customer_invoiceaddr1 = params->{customer_invoiceaddr1} || '';
	my $customer_invoiceaddr2 = params->{customer_invoiceaddr2} || '';
	my $customer_invoicepostcode = params->{customer_invoicepostcode} || '';
	my $customer_invoicecity = params->{customer_invoicecity} || '';
	my $customer_invoicecountry = params->{customer_invoicecountry} || '0';
	my $customer_deliveraddr1 = params->{customer_deliveraddr1} || '';
	my $customer_deliveraddr2 = params->{customer_deliveraddr2} || '';
	my $customer_deliverpostcode = params->{customer_deliverpostcode} || '';
	my $customer_delivercity = params->{customer_delivercity} || '';
	my $customer_delivercountry = params->{customer_delivercountry} || '0';
	my $customer_maincontact = params->{customer_maincontact} || '';
	my $customer_deliveraddr_same_as_invoice = params->{customer_deliveraddr_same_as_invoice} || 'false';
	my $customer_invoiceaddr_same_as_visit = params->{customer_invoiceaddr_same_as_visit} || 'false';
	my $customertype_id_ref = params->{customertype_id_ref} || 1;
	my $customer_site_title = params->{customer_site_title} || '';
	my $dealer_id = params->{dealer_id} || 0;
	
	# test if record allready exists
	my $sth = $mainbase_db_ctl->prepare("SELECT customernumber FROM customer WHERE customernumber='$customernumber'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	if ($result ne "0E0"){
		add2log(2,"Record exists for customernumber:$customernumber.");# Info
		send_error("Record exists for customernumber:$customernumber",302);
	}

	add2log(4,"Adding record for customernumber:$customernumber");# Info
	$sth = $mainbase_db_ctl->prepare( "INSERT INTO customer 
	(customernumber,customer_name,customer_vatnumber,customer_phone,customer_fax,customer_email,customer_web,customer_visitaddr1,customer_visitaddr2,customer_visitpostcode,customer_visitcity,customer_visitcountry,
	customer_invoiceaddr1,customer_invoiceaddr2,customer_invoicepostcode,customer_invoicecity,customer_invoicecountry,customer_deliveraddr1,customer_deliveraddr2,customer_deliverpostcode,customer_delivercity,customer_delivercountry,
	customer_maincontact,customer_deliveraddr_same_as_invoice,customer_invoiceaddr_same_as_visit,customertype_id_ref,customer_site_title,dealer_id)
	VALUES ('$customernumber','$customer_name','$customer_vatnumber','$customer_phone','$customer_fax','$customer_email','$customer_web','$customer_visitaddr1','$customer_visitaddr2','$customer_visitpostcode','$customer_visitcity',$customer_visitcountry,
	'$customer_invoiceaddr1','$customer_invoiceaddr2','$customer_invoicepostcode','$customer_invoicecity',$customer_invoicecountry,'$customer_deliveraddr1','$customer_deliveraddr2','$customer_deliverpostcode','$customer_delivercity',$customer_delivercountry,
	'$customer_maincontact','$customer_deliveraddr_same_as_invoice','$customer_invoiceaddr_same_as_visit',$customertype_id_ref,'$customer_site_title',$dealer_id)");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	return {result=>"OK"};
};

patch '/v1/customers/update' => sub {
	if (not defined params->{customernumber} and not defined params->{customer_id}){
		send_error("Missing parameter: needs customernumber or customer_id",400);
	}
	my $customernumber = params->{customernumber};
	my $customer_id = params->{customer_id};
	# options
	my $customer_name = params->{customer_name};
	my $customer_vatnumber = params->{customer_vatnumber};
	my $customer_phone = params->{customer_phone};
	my $customer_fax = params->{customer_fax};
	my $customer_email = params->{customer_email};
	my $customer_web = params->{customer_web};
	my $customer_visitaddr1 = params->{customer_visitaddr1};
	my $customer_visitaddr2 = params->{customer_visitaddr2};
	my $customer_visitpostcode = params->{customer_visitpostcode};
	my $customer_visitcity = params->{customer_visitcity};
	my $customer_visitcountry = params->{customer_visitcountry};
	my $customer_invoiceaddr1 = params->{customer_invoiceaddr1};
	my $customer_invoiceaddr2 = params->{customer_invoiceaddr2};
	my $customer_invoicepostcode = params->{customer_invoicepostcode};
	my $customer_invoicecity = params->{customer_invoicecity};
	my $customer_invoicecountry = params->{customer_invoicecountry};
	my $customer_deliveraddr1 = params->{customer_deliveraddr1};
	my $customer_deliveraddr2 = params->{customer_deliveraddr2};
	my $customer_deliverpostcode = params->{customer_deliverpostcode};
	my $customer_delivercity = params->{customer_delivercity};
	my $customer_delivercountry = params->{customer_delivercountry};
	my $customer_maincontact = params->{customer_maincontact};
	my $customer_deliveraddr_same_as_invoice = params->{customer_deliveraddr_same_as_invoice};
	my $customer_invoiceaddr_same_as_visit = params->{customer_invoiceaddr_same_as_visit};
	my $customertype_id_ref = params->{customertype_id_ref};
	my $customer_site_title = params->{customer_site_title};
	my $dealer_id = params->{dealer_id};

	my $db_setvalues='';
	if (defined $customer_name and $customer_name ne ''){$db_setvalues.="customer_name='$customer_name',"}
	if (defined $customer_vatnumber and $customer_vatnumber ne ''){$db_setvalues.="customer_vatnumber='$customer_vatnumber',"}
	if (defined $customer_phone and $customer_phone ne ''){$db_setvalues.="customer_phone='$customer_phone',"}
	if (defined $customer_fax and $customer_fax ne ''){$db_setvalues.="customer_fax='$customer_fax',"}
	if (defined $customer_email and $customer_email ne ''){$db_setvalues.="customer_email='$customer_email',"}
	if (defined $customer_web and $customer_web ne ''){$db_setvalues.="customer_web='$customer_web',"}
	if (defined $customer_visitaddr1 and $customer_visitaddr1 ne ''){$db_setvalues.="customer_visitaddr1='$customer_visitaddr1',"}
	if (defined $customer_visitaddr2 and $customer_visitaddr2 ne ''){$db_setvalues.="customer_visitaddr2='$customer_visitaddr2',"}
	if (defined $customer_visitpostcode and $customer_visitpostcode ne ''){$db_setvalues.="customer_visitpostcode='$customer_visitpostcode',"}
	if (defined $customer_visitcity and $customer_visitcity ne ''){$db_setvalues.="customer_visitcity='$customer_visitcity',"}
	if (defined $customer_visitcountry and $customer_visitcountry ne ''){$db_setvalues.="customer_visitcountry='$customer_visitcountry',"}
	if (defined $customer_invoiceaddr1 and $customer_invoiceaddr1 ne ''){$db_setvalues.="customer_invoiceaddr1='$customer_invoiceaddr1',"}
	if (defined $customer_invoiceaddr2 and $customer_invoiceaddr2 ne ''){$db_setvalues.="customer_invoiceaddr2='$customer_invoiceaddr2',"}
	if (defined $customer_invoicepostcode and $customer_invoicepostcode ne ''){$db_setvalues.="customer_invoicepostcode='$customer_invoicepostcode',"}
	if (defined $customer_invoicecity and $customer_invoicecity ne ''){$db_setvalues.="customer_invoicecity='$customer_invoicecity',"}
	if (defined $customer_invoicecountry and $customer_invoicecountry ne ''){$db_setvalues.="customer_invoicecountry='$customer_invoicecountry',"}
	if (defined $customer_deliveraddr1 and $customer_deliveraddr1 ne ''){$db_setvalues.="customer_deliveraddr1='$customer_deliveraddr1',"}
	if (defined $customer_deliveraddr2 and $customer_deliveraddr2 ne ''){$db_setvalues.="customer_deliveraddr2='$customer_deliveraddr2',"}
	if (defined $customer_deliverpostcode and $customer_deliverpostcode ne ''){$db_setvalues.="customer_deliverpostcode='$customer_deliverpostcode',"}
	if (defined $customer_delivercity and $customer_delivercity ne ''){$db_setvalues.="customer_delivercity='$customer_delivercity',"}
	if (defined $customer_delivercountry and $customer_delivercountry ne ''){$db_setvalues.="customer_delivercountry='$customer_delivercountry',"}
	if (defined $customer_maincontact and $customer_maincontact ne ''){$db_setvalues.="customer_maincontact='$customer_maincontact',"}
	if (defined $customer_deliveraddr_same_as_invoice and $customer_deliveraddr_same_as_invoice ne ''){$db_setvalues.="customer_deliveraddr_same_as_invoice='$customer_deliveraddr_same_as_invoice',"}
	if (defined $customer_invoiceaddr_same_as_visit and $customer_invoiceaddr_same_as_visit ne ''){$db_setvalues.="customer_invoiceaddr_same_as_visit='$customer_invoiceaddr_same_as_visit',"}
	if (defined $customertype_id_ref and $customertype_id_ref ne ''){$db_setvalues.="customertype_id_ref='$customertype_id_ref',"}
	if (defined $customer_site_title and $customer_site_title ne ''){$db_setvalues.="customer_site_title='$customer_site_title',"}
	if (defined $dealer_id and $dealer_id ne ''){$db_setvalues.="dealer_id='$dealer_id',"}
	
	if ($db_setvalues eq ''){
		send_error("Missing parameter: needs at least one: customer_name,customer_vatnumber,customer_phone,customer_fax,customer_email,customer_web,customer_visitaddr1,customer_visitaddr2,customer_visitpostcode,customer_visitcity,customer_visitcountry,
	customer_invoiceaddr1,customer_invoiceaddr2,customer_invoicepostcode,customer_invoicecity,customer_invoicecountry,customer_deliveraddr1,customer_deliveraddr2,customer_deliverpostcode,customer_delivercity,customer_delivercountry,
	customer_maincontact,customer_deliveraddr_same_as_invoice,customer_invoicesddr_same_as_visit,customertype_id_ref,customer_site_title",400);
	}
	# remove last char ',' in string
	chop($db_setvalues);

	my $db_where='';
	if (defined $customernumber and $customernumber ne ''){$db_where="customernumber='$customernumber'"}
	if (defined $customer_id and $customer_id ne ''){$db_where="customer_id=$customer_id"}
	
	add2log(4,"Updating record for customernumber:$customernumber with db_setvalues:$db_setvalues");# Info
	my $sth = $mainbase_db_ctl->prepare("UPDATE customer set $db_setvalues where $db_where");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found ssend error
	if ($result eq "0E0"){
		add2log(2,"Missing record for serialnumber:$serialnumber.");# Info
		send_error("Missing record for serialnumber:$serialnumber",404);
	}
	return {result=>"OK"};
};
del '/v1/customers/delete' => sub {
	if (not defined params->{customernumber} and not defined params->{customer_id}){
		send_error("Missing parameter: needs customernumber or customer_id",400);
	}
	my $customernumber = params->{customernumber};
	my $customer_id = params->{customer_id};
	
	my $db_where='';
	if (defined $customernumber and $customernumber ne ''){$db_where="customernumber='$customernumber'"}
	if (defined $customer_id and $customer_id ne ''){$db_where="customer_id=$customer_id"}
	
	add2log(4,"Deleting record for $db_where");# Info
	my $sth = $mainbase_db_ctl->prepare("DELETE from customer where $db_where");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found send error else send OK
	if ($result eq "0E0"){
		send_error("No record for $db_where. $DBI::errstr",404);
  	}else{
   	return{ message =>"OK"};
	}
};


get '/v1/customers/variable/list' => sub {
	my $limit = params->{limit};
	my $offset = params->{offset};
	my $customernumber = params->{customernumber};
	my $variable = params->{variable};
	my $sortfield = params->{sortfield};

	my $db_order_by='';
	if ($sortfield){$db_order_by="ORDER BY $sortfield"}
	my $db_where='';
	if ($customernumber){$db_where="WHERE public.customer_variables.customernumber = '$customernumber'"};
	if ($variable){$db_where.=" and public.customer_variables.variable = $variable"};
	my $db_limit='';
	my $db_offset='';
	if ($limit){$db_limit="LIMIT $limit"}
	if ($offset){$db_offset="OFFSET $offset"}

	my $sth = $mainbase_db_ctl->prepare("SELECT customernumber, variable, value,dateupdated FROM customer_variables $db_where $db_order_by  $db_limit $db_offset");
	
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") customer variables records");# debug
	return{ 'result'=>\@dataset};
};

patch '/v1/customers/variable/update' => sub {
	if (not defined params->{customernumber} or not defined params->{variable} or not defined params->{value}){
		send_error("Missing parameter: needs customernumber, variable and value",400);
	}
	my $customernumber = params->{customernumber};
	my $variable = params->{variable};
	my $value = params->{value};

	my $db_setvalues="value='$value'";
	
	my $sth = $mainbase_db_ctl->prepare("UPDATE customer_variables set $db_setvalues where customernumber='$customernumber' and variable='$variable'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found create record
	if ($result eq "0E0"){
		$sth = $mainbase_db_ctl->prepare( "INSERT INTO customer_variables (customernumber,variable,value) VALUES ('$customernumber','$variable','$value')");
		$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
		add2log(2,"Missing record for customernumber:$customernumber and variable:$variable. Created");# Info
	}
	return {result=>"OK"};
};
del '/v1/customers/variable/delete' => sub {
	if (not params->{customernumber} and not params->{variable}){
		send_error("Missing parameter: needs productnumber, variable",400);
	}
	my $customernumber = params->{customernumber};
	my $variable = params->{variable};
	
	my $db_where="";
	if (defined $customernumber){$db_where="where customernumber='$customernumber'"}
	if (defined $variable){$db_where="and variable='$variable'"}
    
	my $sth = $mainbase_db_ctl->prepare("DELETE from customer_variables $db_where");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found send error else send OK
	if ($result eq "0E0"){
		send_error("No record for customernumber:$customernumber, variable:$variable. $DBI::errstr",404);
	}else{
		return{ message =>"OK"};
	}
};

#
# API for helpdesks
#

get '/v1/helpdesks/list' => sub {
	my $limit = params->{limit};
	my $offset = params->{offset};
	my $helpdesknumber = params->{helpdesknumber};
	my $helpdesk_id = params->{helpdesk_id};
	my $unittype = params->{unittype};
	my $sortfield = params->{sortfield};

	my $db_where='';
	if (defined $helpdesknumber and $helpdesknumber ne ''){$db_where="WHERE helpdesknumber = '$helpdesknumber'"};
	if (defined $helpdesk_id and $helpdesk_id ne ''){$db_where="WHERE helpdesk_id = $helpdesk_id"};
	my $db_order_by='';
	my $db_limit='';
	my $db_offset='';
	if ($sortfield){$db_order_by="ORDER BY $sortfield"} # if defined it should not be 0 or empty
	if ($limit){$db_limit="LIMIT $limit"} # if defined it should not be 0 or empty
	if ($offset){$db_offset="OFFSET $offset"} # if defined it should not be 0 or empty

	add2log(4,"Listing records with parameters $db_where");# Info
	my $sth = $mainbase_db_ctl->prepare("SELECT helpdesknumber,helpdesk_name,helpdesk_vatnumber,helpdesk_phone,helpdesk_fax,helpdesk_email,helpdesk_web,helpdesk_visitaddr1,helpdesk_visitaddr2,helpdesk_visitpostcode,helpdesk_visitcity,helpdesk_visitcountry,
	helpdesk_invoiceaddr1,helpdesk_invoiceaddr2,helpdesk_invoicepostcode,helpdesk_invoicecity,helpdesk_invoicecountry,helpdesk_deliveraddr1,helpdesk_deliveraddr2,helpdesk_deliverpostcode,helpdesk_delivercity,helpdesk_delivercountry,
	helpdesk_maincontact,helpdesk_deliveraddr_same_as_invoice,helpdesk_invoiceaddr_same_as_visit,helpdesk_id
	FROM helpdesks
	$db_where $db_order_by  $db_limit $db_offset");
	
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") queue records URL /v1/helpdesks/list");# debug
	return{ 'result'=>\@dataset};
};
post '/v1/helpdesks/add' => sub {
	if (not defined params->{helpdesknumber}){
		send_error("Missing parameter: needs helpdesknumber",400);
	}
	my $helpdesknumber = params->{helpdesknumber};
	my $helpdesk_name = params->{helpdesk_name} || '';
	my $helpdesk_vatnumber = params->{helpdesk_vatnumber} || '';
	my $helpdesk_phone = params->{helpdesk_phone} || '';
	my $helpdesk_fax = params->{helpdesk_fax} || '';
	my $helpdesk_email = params->{helpdesk_email} || '';
	my $helpdesk_web = params->{helpdesk_web} || '';
	my $helpdesk_visitaddr1 = params->{helpdesk_visitaddr1} || '';
	my $helpdesk_visitaddr2 = params->{helpdesk_visitaddr2} || '';
	my $helpdesk_visitpostcode = params->{helpdesk_visitpostcode} || '';
	my $helpdesk_visitcity = params->{helpdesk_visitcity} || '';
	my $helpdesk_visitcountry = params->{helpdesk_visitcountry} || '';
	my $helpdesk_invoiceaddr1 = params->{helpdesk_invoiceaddr1} || '';
	my $helpdesk_invoiceaddr2 = params->{helpdesk_invoiceaddr2} || '';
	my $helpdesk_invoicepostcode = params->{helpdesk_invoicepostcode} || '';
	my $helpdesk_invoicecity = params->{helpdesk_invoicecity} || '';
	my $helpdesk_invoicecountry = params->{helpdesk_invoicecountry} || '';
	my $helpdesk_deliveraddr1 = params->{helpdesk_deliveraddr1} || '';
	my $helpdesk_deliveraddr2 = params->{helpdesk_deliveraddr2} || '';
	my $helpdesk_deliverpostcode = params->{helpdesk_deliverpostcode} || '';
	my $helpdesk_delivercity = params->{helpdesk_delivercity} || '';
	my $helpdesk_delivercountry = params->{helpdesk_delivercountry} || '';
	my $helpdesk_maincontact = params->{helpdesk_maincontact} || '';
	my $helpdesk_deliveraddr_same_as_invoice = params->{helpdesk_deliveraddr_same_as_invoice} || 'false';
	my $helpdesk_invoiceaddr_same_as_visit = params->{helpdesk_invoiceaddr_same_as_visit} || 'false';

	# test if record allready exists
	my $sth = $mainbase_db_ctl->prepare("SELECT helpdesknumber FROM helpdesks WHERE helpdesknumber='$helpdesknumber'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	if ($result ne "0E0"){
		add2log(2,"Record exists for helpdesknumber:$helpdesknumber.");# Info
		send_error("Record exists for helpdesknumber:$helpdesknumber",302);
	}

	add2log(4,"Adding record for helpdesknumber:$helpdesknumber");# Info
	$sth = $mainbase_db_ctl->prepare( "INSERT INTO helpdesks 
	(helpdesknumber,helpdesk_name,helpdesk_vatnumber,helpdesk_phone,helpdesk_fax,helpdesk_email,helpdesk_web,helpdesk_visitaddr1,helpdesk_visitaddr2,helpdesk_visitpostcode,helpdesk_visitcity,helpdesk_visitcountry,
	helpdesk_invoiceaddr1,helpdesk_invoiceaddr2,helpdesk_invoicepostcode,helpdesk_invoicecity,helpdesk_invoicecountry,helpdesk_deliveraddr1,helpdesk_deliveraddr2,helpdesk_deliverpostcode,helpdesk_delivercity,helpdesk_delivercountry,
	helpdesk_maincontact,helpdesk_deliveraddr_same_as_invoice,helpdesk_invoiceaddr_same_as_visit)
	VALUES ('$helpdesknumber','$helpdesk_name','$helpdesk_vatnumber','$helpdesk_phone','$helpdesk_fax','$helpdesk_email','$helpdesk_web','$helpdesk_visitaddr1','$helpdesk_visitaddr2','$helpdesk_visitpostcode','$helpdesk_visitcity','$helpdesk_visitcountry',
	'$helpdesk_invoiceaddr1','$helpdesk_invoiceaddr2','$helpdesk_invoicepostcode','$helpdesk_invoicecity','$helpdesk_invoicecountry','$helpdesk_deliveraddr1','$helpdesk_deliveraddr2','$helpdesk_deliverpostcode','$helpdesk_delivercity','$helpdesk_delivercountry',
	'$helpdesk_maincontact','$helpdesk_deliveraddr_same_as_invoice','$helpdesk_invoiceaddr_same_as_visit')");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	return {result=>"OK"};
};

patch '/v1/helpdesks/update' => sub {
	if (not defined params->{helpdesknumber} and not defined params->{helpdesk_id}){
		send_error("Missing parameter: needs helpdesknumber or helpdesk_id",400);
	}
	my $helpdesknumber = params->{helpdesknumber};
	my $helpdesk_id = params->{helpdesk_id};
	# options
	my $helpdesk_name = params->{helpdesk_name};
	my $helpdesk_vatnumber = params->{helpdesk_vatnumber};
	my $helpdesk_phone = params->{helpdesk_phone};
	my $helpdesk_fax = params->{helpdesk_fax};
	my $helpdesk_email = params->{helpdesk_email};
	my $helpdesk_web = params->{helpdesk_web};
	my $helpdesk_visitaddr1 = params->{helpdesk_visitaddr1};
	my $helpdesk_visitaddr2 = params->{helpdesk_visitaddr2};
	my $helpdesk_visitpostcode = params->{helpdesk_visitpostcode};
	my $helpdesk_visitcity = params->{helpdesk_visitcity};
	my $helpdesk_visitcountry = params->{helpdesk_visitcountry};
	my $helpdesk_invoiceaddr1 = params->{helpdesk_invoiceaddr1};
	my $helpdesk_invoiceaddr2 = params->{helpdesk_invoiceaddr2};
	my $helpdesk_invoicepostcode = params->{helpdesk_invoicepostcode};
	my $helpdesk_invoicecity = params->{helpdesk_invoicecity};
	my $helpdesk_invoicecountry = params->{helpdesk_invoicecountry};
	my $helpdesk_deliveraddr1 = params->{helpdesk_deliveraddr1};
	my $helpdesk_deliveraddr2 = params->{helpdesk_deliveraddr2};
	my $helpdesk_deliverpostcode = params->{helpdesk_deliverpostcode};
	my $helpdesk_delivercity = params->{helpdesk_delivercity};
	my $helpdesk_delivercountry = params->{helpdesk_delivercountry};
	my $helpdesk_maincontact = params->{helpdesk_maincontact};
	my $helpdesk_deliveraddr_same_as_invoice = params->{helpdesk_deliveraddr_same_as_invoice};
	my $helpdesk_invoiceaddr_same_as_visit = params->{helpdesk_invoiceaddr_same_as_visit};

	my $db_setvalues='';
	if (defined $helpdesk_name and $helpdesk_name ne ''){$db_setvalues.="helpdesk_name='$helpdesk_name',"}
	if (defined $helpdesk_vatnumber and $helpdesk_vatnumber ne ''){$db_setvalues.="helpdesk_vatnumber='$helpdesk_vatnumber',"}
	if (defined $helpdesk_phone and $helpdesk_phone ne ''){$db_setvalues.="helpdesk_phone='$helpdesk_phone',"}
	if (defined $helpdesk_fax and $helpdesk_fax ne ''){$db_setvalues.="helpdesk_fax='$helpdesk_fax',"}
	if (defined $helpdesk_email and $helpdesk_email ne ''){$db_setvalues.="helpdesk_email='$helpdesk_email',"}
	if (defined $helpdesk_web and $helpdesk_web ne ''){$db_setvalues.="helpdesk_web='$helpdesk_web',"}
	if (defined $helpdesk_visitaddr1 and $helpdesk_visitaddr1 ne ''){$db_setvalues.="helpdesk_visitaddr1='$helpdesk_visitaddr1',"}
	if (defined $helpdesk_visitaddr2 and $helpdesk_visitaddr2 ne ''){$db_setvalues.="helpdesk_visitaddr2='$helpdesk_visitaddr2',"}
	if (defined $helpdesk_visitpostcode and $helpdesk_visitpostcode ne ''){$db_setvalues.="helpdesk_visitpostcode='$helpdesk_visitpostcode',"}
	if (defined $helpdesk_visitcity and $helpdesk_visitcity ne ''){$db_setvalues.="helpdesk_visitcity='$helpdesk_visitcity',"}
	if (defined $helpdesk_visitcountry and $helpdesk_visitcountry ne ''){$db_setvalues.="helpdesk_visitcountry='$helpdesk_visitcountry',"}
	if (defined $helpdesk_invoiceaddr1 and $helpdesk_invoiceaddr1 ne ''){$db_setvalues.="helpdesk_invoiceaddr1='$helpdesk_invoiceaddr1',"}
	if (defined $helpdesk_invoiceaddr2 and $helpdesk_invoiceaddr2 ne ''){$db_setvalues.="helpdesk_invoiceaddr2='$helpdesk_invoiceaddr2',"}
	if (defined $helpdesk_invoicepostcode and $helpdesk_invoicepostcode ne ''){$db_setvalues.="helpdesk_invoicepostcode='$helpdesk_invoicepostcode',"}
	if (defined $helpdesk_invoicecity and $helpdesk_invoicecity ne ''){$db_setvalues.="helpdesk_invoicecity='$helpdesk_invoicecity',"}
	if (defined $helpdesk_invoicecountry and $helpdesk_invoicecountry ne ''){$db_setvalues.="helpdesk_invoicecountry='$helpdesk_invoicecountry',"}
	if (defined $helpdesk_deliveraddr1 and $helpdesk_deliveraddr1 ne ''){$db_setvalues.="helpdesk_deliveraddr1='$helpdesk_deliveraddr1',"}
	if (defined $helpdesk_deliveraddr2 and $helpdesk_deliveraddr2 ne ''){$db_setvalues.="helpdesk_deliveraddr2='$helpdesk_deliveraddr2',"}
	if (defined $helpdesk_deliverpostcode and $helpdesk_deliverpostcode ne ''){$db_setvalues.="helpdesk_deliverpostcode='$helpdesk_deliverpostcode',"}
	if (defined $helpdesk_delivercity and $helpdesk_delivercity ne ''){$db_setvalues.="helpdesk_delivercity='$helpdesk_delivercity',"}
	if (defined $helpdesk_delivercountry and $helpdesk_delivercountry ne ''){$db_setvalues.="helpdesk_delivercountry='$helpdesk_delivercountry',"}
	if (defined $helpdesk_maincontact and $helpdesk_maincontact ne ''){$db_setvalues.="helpdesk_maincontact='$helpdesk_maincontact',"}
	if (defined $helpdesk_deliveraddr_same_as_invoice and $helpdesk_deliveraddr_same_as_invoice ne ''){$db_setvalues.="helpdesk_deliveraddr_same_as_invoice='$helpdesk_deliveraddr_same_as_invoice',"}
	if (defined $helpdesk_invoiceaddr_same_as_visit and $helpdesk_invoiceaddr_same_as_visit ne ''){$db_setvalues.="helpdesk_invoiceaddr_same_as_visit='$helpdesk_invoiceaddr_same_as_visit',"}
	
	if ($db_setvalues eq ''){
		send_error("Missing parameter: needs at least one: helpdesk_name,helpdesk_vatnumber,helpdesk_phone,helpdesk_fax,helpdesk_email,helpdesk_web,helpdesk_visitaddr1,helpdesk_visitaddr2,helpdesk_visitpostcode,helpdesk_visitcity,helpdesk_visitcountry,
	helpdesk_invoiceaddr1,helpdesk_invoiceaddr2,helpdesk_invoicepostcode,helpdesk_invoicecity,helpdesk_invoicecountry,helpdesk_deliveraddr1,helpdesk_deliveraddr2,helpdesk_deliverpostcode,helpdesk_delivercity,helpdesk_delivercountry,
	helpdesk_maincontact,helpdesk_deliveraddr_same_as_invoice,helpdesk_invoicesddr_same_as_visit",400);
	}
	# remove last char ',' in string
	chop($db_setvalues);

	my $db_where='';
	if (defined $helpdesknumber and $helpdesknumber ne ''){$db_where="helpdesknumber='$helpdesknumber'"}
	if (defined $helpdesk_id and $helpdesk_id ne ''){$db_where="helpdesk_id=$helpdesk_id"}
	
	add2log(4,"Updating record for helpdesknumber:$helpdesknumber with db_setvalues:$db_setvalues");# Info
	my $sth = $mainbase_db_ctl->prepare("UPDATE helpdesks set $db_setvalues where $db_where");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found ssend error
	if ($result eq "0E0"){
		add2log(2,"Missing record for serialnumber:$serialnumber.");# Info
		send_error("Missing record for serialnumber:$serialnumber",404);
	}
	return {result=>"OK"};
};
del '/v1/helpdesks/delete' => sub {
	if (not defined params->{helpdesknumber} and not defined params->{helpdesk_id}){
		send_error("Missing parameter: needs helpdesknumber or helpdesk_id",400);
	}
	my $helpdesknumber = params->{helpdesknumber};
	my $helpdesk_id = params->{helpdesk_id};
	
	my $db_where='';
	if (defined $helpdesknumber and $helpdesknumber ne ''){$db_where="helpdesknumber='$helpdesknumber'"}
	if (defined $helpdesk_id and $helpdesk_id ne ''){$db_where="helpdesk_id=$helpdesk_id"}
	
	add2log(4,"Deleting record for $db_where");# Info
	my $sth = $mainbase_db_ctl->prepare("DELETE from helpdesks where $db_where");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found send error else send OK
	if ($result eq "0E0"){
		send_error("No record for $db_where. $DBI::errstr",404);
  	}else{
   	return{ message =>"OK"};
	}
};
#
# API for messages
#

get '/v1/messages/list' => sub {
	my $limit = params->{limit};
	my $offset = params->{offset};
	my $customernumber = params->{customernumber};
	my $customer_id_ref = params->{customer_id_ref};
	my $serialnumber = params->{serialnumber};
	my $sortfield = params->{sortfield};

	my $db_where='';
	if (defined $customernumber){
		$db_where="WHERE customer.customernumber = '$customernumber'";
		if (defined $serialnumber){$db_where="WHERE customer.customernumber = '$customernumber' and serialnumber='$serialnumber'"};
	};
	if (defined $customer_id_ref){
		$db_where="WHERE customer_id_ref = '$customer_id_ref'";
		if (defined $serialnumber){$db_where="WHERE customer_id_ref = $customer_id_ref and serialnumber='$serialnumber'"};
	};
	if (defined $serialnumber and not defined $customernumber and not defined $customer_id_ref){$db_where="WHERE serialnumber = '$serialnumber'"};
	
	my $db_order_by='order by timestamp desc';
	#my $db_order_by='';
	my $db_limit='';
	my $db_offset='';
	if ($sortfield){$db_order_by="ORDER BY $sortfield"} # if defined it should not be 0 or empty
	if ($limit){$db_limit="LIMIT $limit"} # if defined it should not be 0 or empty
	if ($offset){$db_offset="OFFSET $offset"} # if defined it should not be 0 or empty

	add2log(4,"Listing message records with db_were:$db_where");# Info
	my $sth = $mainbase_db_ctl->prepare("SELECT archived,message,timestamp,checkedbyuser,serialnumber,message_id,customer_id,customer.customernumber FROM messages
	INNER JOIN public.customer ON (public.customer.customer_id = customer_id_ref)
	$db_where $db_order_by  $db_limit $db_offset");
	
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") message records. api:/messages/list");# debug
	return{ 'result'=>\@dataset};
};
post '/v1/messages/add' => sub {
	if (not defined params->{message} or not defined params->{serialnumber} or (not defined params->{customernumber} and not defined params->{customer_id_ref})){
		send_error("Missing parameter: needs message, serialnumber, (customernumber or customer_id_ref)",400);
	}
	my $customernumber = params->{customernumber};
	my $message = params->{message};
	my $serialnumber = params->{serialnumber};
	my $customer_id_ref = params->{customer_id_ref};
	# If customer number get customer_id
	my $sth='';
	if ($customernumber){
		$sth = $mainbase_db_ctl->prepare("SELECT customer_id FROM customer WHERE customernumber='$customernumber'");
		my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
		my $row=$sth->fetchrow_hashref();
		$sth->finish();
		if ($result eq "0E0"){
			add2log(2,"Record does not exists for customernumber:$customernumber");# Info
			send_error("Record does not exists for customernumber:$customernumber",302);
		}
		$customer_id_ref=$row->{'customer_id'};
	}

	add2log(4,"Adding message record for customer_id_ref:$customer_id_ref, serialnumber:$serialnumber, message:$message.");# Info
	$sth = $mainbase_db_ctl->prepare( "INSERT INTO messages (customer_id_ref,serialnumber, message,timestamp) VALUES ($customer_id_ref,'$serialnumber','$message',current_timestamp)");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	return {result=>"OK"};
};

patch '/v1/messages/update' => sub {
	if (not defined params->{message_id} or not defined params->{archived} or not defined params->{checkedbyuser}){
		send_error("Missing parameter: needs message_id, archived, checkedbyuser",400);
	}
	my $message_id = params->{message_id};
	my $checkedbyuser = params->{checkedbyuser};
	my $archived = params->{archived};

	my $db_setvalues="archived='$archived',checkedbyuser='$checkedbyuser'";
	
	add2log(4,"Updating record for message_id:$message_id with db_setvalues:$db_setvalues");# Info
	my $sth = $mainbase_db_ctl->prepare("UPDATE messages set $db_setvalues where message_id=$message_id");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	if ($result eq "0E0"){
			add2log(2,"Record does not exists for message_id:$message_id");# Info
			send_error("Record does not exists for message_id:$message_id",302);
	}
	return {result=>"OK"};
};
del '/v1/messages/delete' => sub {
	if (not defined params->{message_id}){
		send_error("Missing parameter: needs message_id",400);
	}
	my $message_id = params->{message_id};

	add2log(4,"Deleting record for message_id:$message_id");# Info
	my $sth = $mainbase_db_ctl->prepare("DELETE from messages where message_id=$message_id");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found send error else send OK
	if ($result eq "0E0"){
		send_error("No record for message_id:$message_id. $DBI::errstr",404);
  	}else{
   	return{ message =>"OK"};
	}
};

#
# API for messages
#

get '/v1/customertypes/list' => sub {
	my $limit = params->{limit};
	my $offset = params->{offset};
	my $sortfield = params->{sortfield};

	my $db_order_by='';
	my $db_limit='';
	my $db_offset='';
	if ($sortfield){$db_order_by="ORDER BY $sortfield"} # if defined it should not be 0 or empty
	if ($limit){$db_limit="LIMIT $limit"} # if defined it should not be 0 or empty
	if ($offset){$db_offset="OFFSET $offset"} # if defined it should not be 0 or empty

	add2log(4,"Listing cystomertypes records");# Info
	my $sth = $mainbase_db_ctl->prepare("SELECT customertype,description,customertype_id FROM customertype $db_order_by  $db_limit $db_offset");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") queue records URL /v1/customertypes/list");# debug
	return{ 'result'=>\@dataset};
};
post '/v1/customertypes/add' => sub {
	if (not defined params->{customertype} or not defined params->{description}){
		send_error("Missing parameter: needs customertype and description",400);
	}
	my $customertype = params->{customertype};
	my $description = params->{description};
	
	add2log(4,"Adding record for customertype:$customertype, description:$description.");# Info
	my $sth = $mainbase_db_ctl->prepare( "INSERT INTO customertype (customertype,description) VALUES ('$customertype','$description')");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	return {result=>"OK"};
};

patch '/v1/customertypes/update' => sub {
	if (not defined params->{customertype_id}){
		send_error("Missing parameter: needs customertype_id",400);
	}
	my $customertype_id = params->{customertype_id};
	my $customertype = params->{customertype};
	my $description = params->{description};

	my $db_setvalues='';
	if (defined $description){$db_setvalues.="description='$description',"}
	if (defined $customertype){$db_setvalues.="customertype='$customertype',"}
	if ($db_setvalues eq ''){
		send_error("Missing parameter: needs at least one: customertype, description",400);
	}
	# remove last char ',' in string
	chop($db_setvalues);
	
	add2log(4,"Updating record for customertype_id:$customertype_id with db_setvalues:$db_setvalues");# Info
	my $sth = $mainbase_db_ctl->prepare("UPDATE customertype set $db_setvalues where customertype_id=$customertype_id");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found error
	if ($result eq "0E0"){
			add2log(2,"Record does not exists for customertype_id:$customertype_id");# Info
			send_error("Record does not exists for customertype_id:$customertype_id",302);
	}
	return {result=>"OK"};
};
del '/v1/customertypes/delete' => sub {
	if (not defined params->{customertype_id}){
		send_error("Missing parameter: needs customertype_id",400);
	}
	my $customertype_id = params->{customertype_id};
	my $db_where="customertype_id=$customertype_id";
	
	add2log(4,"Deleting record for $db_where");# Info
	my $sth = $mainbase_db_ctl->prepare("DELETE from customertype where $db_where");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found send error else send OK
	if ($result eq "0E0"){
		send_error("No record for $db_where.",404);
  	}else{
   	return{ message =>"OK"};
	}
};


######################################################################
#
# API GUI viewgroup
#
# List viewgroups with groupname and order. Filter on serialnumber or customernumber
get '/v1/gui/viewgroup/list' => sub {
	my $customernumber = params->{customernumber};

	my $limit = params->{limit};
	my $offset = params->{offset};
	my $sortfield = params->{sortfield};

	my $db_where='';
	if (defined $customernumber){$db_where="WHERE customernumber = '$customernumber'"};

	my $db_order_by='';
	my $db_limit='';
	my $db_offset='';
	if ($sortfield){$db_order_by="ORDER BY $sortfield"} # if defined it should not be 0 or empty
	if ($limit){$db_limit="LIMIT $limit"} # if defined it should not be 0 or empty
	if ($offset){$db_offset="OFFSET $offset"} # if defined it should not be 0 or empty

	add2log(4,"Listing viewgroup records with parameters customernumber:$customernumber");# Info
	my $sth = $mainbase_db_ctl->prepare("SELECT viewgroup_id, viewgroup_name, viewgroup_description, customernumber
	FROM gui_viewgroup
	$db_where $db_order_by  $db_limit $db_offset");
	
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") queue records URL /v1/gui/viewgroup/list");# debug
	return{ 'result'=>\@dataset};
};
# add a new viewgroup with customernumber, name and description
post '/v1/gui/viewgroup/add' => sub {
	if (not defined params->{customernumber} or not defined params->{viewgroup_name}){
		send_error("Missing parameter: needs customernumber and viewgroup_name. Option viewgroup_description",400);
	}
	my $customernumber = params->{customernumber};
	my $viewgroup_name = params->{viewgroup_name};
	my $viewgroup_description = params->{viewgroup_description} || '';
	
	# test if record already exists
	my $sth = $mainbase_db_ctl->prepare("SELECT viewgroup_name FROM gui_viewgroup WHERE customernumber='$customernumber' AND viewgroup_name='$viewgroup_name'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	if ($result ne "0E0"){
		add2log(2,"Record exists for customernumber:$customernumber and viewgroup_name:$viewgroup_name.");# Info
		send_error("Record exists for customernumber:$customernumber and viewgroup_name:$viewgroup_name",302);
	}

	add2log(4,"Adding record for customernumber:$customernumber, viewgroup_name:$viewgroup_name, viewgroup_description:$viewgroup_description.");# Info
	$sth = $mainbase_db_ctl->prepare( "INSERT INTO gui_viewgroup (customernumber,viewgroup_name,viewgroup_description) VALUES ('$customernumber','$viewgroup_name','$viewgroup_description')");
	$result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	return {result=>"OK"};
};
# Update viewgroup name and description
patch '/v1/gui/viewgroup/update' => sub {
	if (not defined params->{viewgroup_id}){
		send_error("Missing parameter: needs viewgroup_id",400);
	}
	my $viewgroup_id = params->{viewgroup_id};
	my $viewgroup_name = params->{viewgroup_name};
	my $viewgroup_description = params->{viewgroup_description};

	my $db_setvalues='';
	if (defined $viewgroup_name){$db_setvalues.="viewgroup_name='$viewgroup_name',"}
	if (defined $viewgroup_description){$db_setvalues.="viewgroup_description='$viewgroup_description',"}
	if ($db_setvalues eq ''){
		send_error("Missing parameter: needs at least one: viewgroup_name, viewgroup_description",400);
	}
	# remove last char ',' in string
	chop($db_setvalues);
	
	add2log(4,"Updating record for viewgroup_id:$viewgroup_id with db_setvalues:$db_setvalues");# Info
	my $sth = $mainbase_db_ctl->prepare("UPDATE gui_viewgroup set $db_setvalues where viewgroup_id=$viewgroup_id");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found create record
	if ($result eq "0E0"){
		send_error("Missing record for viewgroup_id:$viewgroup_id. Please add first");# Info
		add2log(2,"Missing record for viewgroup_id:$viewgroup_id");# Info
	}
	return {result=>"OK"};
};
del '/v1/gui/viewgroup/delete' => sub {
	if (not defined params->{viewgroup_id}){
		send_error("Missing parameter: needs viewgroup_id)",400);
	}
	my $viewgroup_id = params->{viewgroup_id};
	
	my $db_where='';
	if (defined $viewgroup_id and $viewgroup_id ne ''){$db_where="viewgroup_id=$viewgroup_id"}
	
	add2log(4,"Deleting record for $db_where");# Info
	my $sth = $mainbase_db_ctl->prepare("DELETE from gui_viewgroup where $db_where");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found send error else send OK
	if ($result eq "0E0"){
		send_error("No record for $db_where.",302);
  	}else{
   	return{ message =>"OK"};
	}
};
#
# List order and groups
# 04.03.25: Serhat har lagt til standard sortering på viewgroup_order om annet ikke er oppgitt, og en AND istede for WHERE i SQL spørringen.

get '/v1/gui/viewgroup/order/list' => sub {
    my $serialnumber   = params->{serialnumber};
    my $customernumber = params->{customernumber};
 
    my $limit     = params->{limit};
    my $offset    = params->{offset};
    my $sortfield = params->{sortfield};
 
	my $db_where = '';
	if (defined $serialnumber) { $db_where = "WHERE serialnumber = '$serialnumber'" };
	if (defined $customernumber) {
		if ($db_where eq '') {
			$db_where = "WHERE customernumber = '$customernumber'";
		} else {
			$db_where .= " AND customernumber = '$customernumber'";
		}
	} 
	
    my $db_order_by = '';
    my $db_limit    = '';
    my $db_offset   = '';
 
    #  Set default ordering by viewgroup_order if sortfield is not provided 
    if ($sortfield) {
        $db_order_by = "ORDER BY $sortfield";
    } else {
        $db_order_by = "ORDER BY viewgroup_order";
    }
    if ($limit)  { $db_limit  = "LIMIT $limit"; }
    if ($offset) { $db_offset = "OFFSET $offset"; }
    if (not defined $serialnumber) { $serialnumber = '' }
    if (not defined $customernumber) { $customernumber = '' }
    add2log(4, "Listing viewgroup order records with parameters serialnumber:$serialnumber, customernumber:$customernumber");
    my $sth = $mainbase_db_ctl->prepare("SELECT viewgroup_order_id, serialnumber, viewgroup_id_ref, viewgroup_order, viewgroup_id, viewgroup_name, viewgroup_description, customernumber
        FROM gui_viewgroup_order
        INNER JOIN gui_viewgroup ON (viewgroup_id_ref = viewgroup_id)
        $db_where $db_order_by $db_limit $db_offset");
    $sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
    my @dataset = ();
    while (my $row = $sth->fetchrow_hashref()) {
        push (@dataset, $row);
    }
    $sth->finish();
    add2log(4, "Fetched (" . scalar(@dataset) . ") queue records URL /v1/gui/viewgroup/order/list");
    return { 'result' => \@dataset };
};

#
# add a new viewgroup ORDER with serialnumber,viewgroup_name_id_ref,viewgroup_order
post '/v1/gui/viewgroup/order/add' => sub {
	if (not defined params->{serialnumber} or not defined params->{viewgroup_id_ref} or not defined params->{viewgroup_order}){
		send_error("Missing parameter: needs serialnumber, viewgroup_id_ref and viewgroup_order",400);
	}
	my $serialnumber = params->{serialnumber};
	my $viewgroup_id_ref = params->{viewgroup_id_ref};
	my $viewgroup_order = params->{viewgroup_order};
	
	# test if record already exists
	my $sth = $mainbase_db_ctl->prepare("SELECT viewgroup_order_id FROM gui_viewgroup_order WHERE serialnumber='$serialnumber'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	if ($result ne "0E0"){
		add2log(2,"Record viewgroup_order exists for serialnumber:$serialnumber.");# Info
		send_error("Record viewgroup_order exists for serialnumber:$serialnumber",302);
	}

	add2log(4,"Adding record for serialnumber:$serialnumber, viewgroup_id_ref:$viewgroup_id_ref, viewgroup_order:$viewgroup_order.");# Info
	$sth = $mainbase_db_ctl->prepare( "INSERT INTO gui_viewgroup_order (serialnumber,viewgroup_id_ref,viewgroup_order) VALUES ('$serialnumber',$viewgroup_id_ref,$viewgroup_order)");
	$result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	return {result=>"OK"};
};
# Update viewgroup order. Will NOT create record if not exists. Update via serialnumber or viewgroup_id
patch '/v1/gui/viewgroup/order/update' => sub {
	if (not defined params->{viewgroup_order_id} and not defined params->{serialnumber}){
		send_error("Missing parameter: needs viewgroup_order_id or serialnumber. Option: viewgroup_id_ref and/or viewgroup_order",400);
	}
	my $viewgroup_order_id = params->{viewgroup_order_id};
	my $serialnumber = params->{serialnumber};
	my $viewgroup_id_ref = params->{viewgroup_id_ref};
	my $viewgroup_order = params->{viewgroup_order};

	my $db_setvalues='';
	if (defined $viewgroup_id_ref){$db_setvalues.="viewgroup_id_ref='$viewgroup_id_ref',"}
	if (defined $viewgroup_order){$db_setvalues.="viewgroup_order='$viewgroup_order',"}
	if ($db_setvalues eq ''){
		send_error("Missing parameter: needs at least one: viewgroup_id_ref, viewgroup_order",400);
	}
	# remove last char ',' in string
	chop($db_setvalues);
	
	my $db_where='';
	if (defined $viewgroup_order_id){$db_where="viewgroup_order_id=$viewgroup_order_id"}
	if (defined $serialnumber and $serialnumber ne ''){$db_where="serialnumber='$serialnumber'"}
	
	add2log(4,"Updating record for viewgroup_order_id:$viewgroup_order_id with db_setvalues:$db_setvalues");# Info
	my $sth = $mainbase_db_ctl->prepare("UPDATE gui_viewgroup_order set $db_setvalues where $db_where");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found create record
	if ($result eq "0E0"){
		send_error("Missing record for viewgroup_order_id:$viewgroup_order_id or serialnumber:$serialnumber. Please add first");# Info
		add2log(2,"Missing record for viewgroup_order_id:$viewgroup_order_id or serialnumber:$serialnumber");# Info
	}
	return {result=>"OK"};
};
# Delete group view order. Uses serialnumber or viewgroup_id
del '/v1/gui/viewgroup/order/delete' => sub {
	if (not defined params->{viewgroup_order_id} and not defined params->{serialnumber}){
		send_error("Missing parameter: needs viewgroup_id or serialnumber)",400);
	}
	my $viewgroup_order_id = params->{viewgroup_order_id};
	my $serialnumber = params->{serialnumber};
	
	my $db_where='';
	if (defined $viewgroup_order_id and $viewgroup_order_id ne ''){$db_where="viewgroup_order_id=$viewgroup_order_id"}
	if (defined $serialnumber and $serialnumber ne ''){$db_where="serialnumber='$serialnumber'"}
	
	add2log(4,"Deleting record for $db_where");# Info
	my $sth = $mainbase_db_ctl->prepare("DELETE from gui_viewgroup_order where $db_where");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not found send error else send OK
	if ($result eq "0E0"){
		send_error("No record for $db_where.",302);
  	}else{
   	return{ message =>"OK"};
	}
};
######################################################################
#
# API variable type
#
# List variabletypes with groupname and order. Filter on serialnumber or customernumber

get '/v1/variabletypes/list' => sub {
	my $variabletypes_type = params->{variables_types_type};

	my $limit = params->{limit};
	my $offset = params->{offset};
	my $sortfield = params->{sortfield};

	my $db_order_by='';
	if ($sortfield){$db_order_by="ORDER BY $sortfield"}
	my $db_where='';
	if (defined $variabletypes_type){$db_where="WHERE public.variable_types.variable_types_type = $variabletypes_type"};
	my $db_limit='';
	my $db_offset='';
	if ($limit){$db_limit="LIMIT $limit"}
	if ($offset){$db_offset="OFFSET $offset"}

	my $sth = $mainbase_db_ctl->prepare("SELECT variable_types_variable, variable_types_type, variable_types_defaultvalue,variable_types_dateupdated FROM variable_types $db_where $db_order_by $db_limit $db_offset");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my @dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@dataset,$row);
	}
	$sth->finish();
	add2log(4,"Fetched (".scalar(@dataset).") variablestype records");# debug
	return{ 'result'=>\@dataset};
};
######################################################################
#
# API countries type
#
# List countries. Filter on countries_id or customernumber
get '/v1/countries/list' => sub {
    my $limit = params->{limit};
    my $offset = params->{offset};
    my $country_id = params->{country_id};
    my $variable = params->{variable};
    my $sortfield = params->{sortfield};

    my $db_order_by='';
    if ($sortfield){$db_order_by="ORDER BY $sortfield"}
    my $db_where='';
    if ($country_id){$db_where="WHERE public.countries.country_id = '$country_id'"};
    my $db_limit='';
    my $db_offset='';
    if ($limit){$db_limit="LIMIT $limit"}
    if ($offset){$db_offset="OFFSET $offset"}

    my $sth = $mainbase_db_ctl->prepare("SELECT country_id, name FROM countries $db_where $db_order_by  $db_limit $db_offset");
    
    $sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
    my @dataset=();
    while (my $row=$sth->fetchrow_hashref()){
        push (@dataset,$row);
    }
    $sth->finish();
    add2log(4,"Fetched (".scalar(@dataset).") countries records");# debug
    return{ 'result'=>\@dataset};
};
patch '/v1/sensordata/rename' => sub {
    if (not params->{dbname} ){
        send_error("Missing parameter, needs dbname",400);
    }
    my $dbname = params->{dbname};

    #return{ 'result'=>\@dataset};
		# Open customer sensordata database
		my $sensordata_db_ctl = DBI->connect("dbi:Pg:dbname=$dbname;host=localhost;port=5432",'admin_db','onesnes78', {AutoCommit => 1, RaiseError => 1 }) or die $DBI::errstr; 
    my $sth = $sensordata_db_ctl->prepare(" ALTER TABLE sensordata RENAME COLUMN sensornumber TO probenumber");
    my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
    # check if we found DB
    if ($result eq "0E0"){
        send_error("Did not upate:$dbname",400);
    }

    $sth->finish();
    # Remove database name from set
    return{ message =>"OK"};

};
#
# Move sensor to customer
patch '/v1/sensorunit/move2customer' => sub {
    # Check if missing parameter
    if (not params->{serialnumber} or not params->{customernumber}){
        send_error("Missing parameter: needs serialnumber and customernumber");
    }
    my $serialnumber = params->{serialnumber};
    my $customernumber = params->{customernumber};
    
    # Find sensorunit_id og eksisterende customernumber
    my $sth = $mainbase_db_ctl->prepare("SELECT sensorunit_id, customernumber FROM sensorunits WHERE serialnumber='$serialnumber'");
    my $result = $sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
    if ($result eq "0E0"){
        add2log(2,"/v1/sensorunit/move2customer: Did not find serialnumber: $serialnumber");# info
        send_error("Did not find serialnumber: $serialnumber",400);
    }
    my $row = $sth->fetchrow_hashref();
    # Returner tidlig dersom customernumber er lik den som allerede er registrert
    if ($row->{customernumber} eq $customernumber) {
        add2log(3,"/v1/sensorunit/move2customer: No change needed for serialnumber:$serialnumber as customernumber is the same");
        return { message => "No change needed" };
    }
    my $sensorunit_id = $row->{sensorunit_id};
    
    # Delete current access
    $sth = $mainbase_db_ctl->prepare("DELETE FROM sensoraccess WHERE serialnumber='$serialnumber'");
    $result = $sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
    $sth->finish();
    
    # Delete current message receivers
    $sth = $mainbase_db_ctl->prepare("DELETE FROM message_receivers WHERE sensorunits_id_ref=$sensorunit_id");
    $result = $sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
    $sth->finish();
    
    # Delete sensor from viewgroup_order
    $sth = $mainbase_db_ctl->prepare("DELETE FROM gui_viewgroup_order WHERE serialnumber='$serialnumber'");
    $result = $sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
    $sth->finish();
    
    # Find customer_id
    $sth = $mainbase_db_ctl->prepare("SELECT customer_id FROM customer WHERE customernumber='$customernumber'");
    $result = $sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
    if ($result eq "0E0"){
        add2log(2,"/v1/sensorunit/move2customer: Did not find customernumber: $customernumber");# Error
        send_error("Did not find customernumber: $customernumber",400);
    }
    $row = $sth->fetchrow_hashref();
    my $customer_id = $row->{customer_id};
    
    # Find new user list for kunden
    $sth = $mainbase_db_ctl->prepare("SELECT user_id FROM users WHERE customer_id_ref=$customer_id");
    $sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
    my @dataset = ();
    while ($row = $sth->fetchrow_hashref()){
        push (@dataset, $row);
    }
    $sth->finish();
    
    # Opprett nye access og message_receivers for hver bruker
    foreach my $users_hash (@dataset){
        my $user_id = $users_hash->{user_id};
        $sth = $mainbase_db_ctl->prepare("INSERT INTO sensoraccess (user_id, serialnumber, changeallowed) VALUES ($user_id, '$serialnumber', true)");
        $sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
        $sth = $mainbase_db_ctl->prepare("INSERT INTO message_receivers (users_id_ref, sensorunits_id_ref) VALUES ($user_id, $sensorunit_id)");
        $sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
    }
    
    # Endre sensorunits record til den nye kunden
    my $database_name = "sensordata_" . substr($customernumber,3,4);
    $sth = $mainbase_db_ctl->prepare("UPDATE sensorunits SET customernumber='$customernumber', customer_id_ref=$customer_id, dbname='$database_name' WHERE serialnumber='$serialnumber'");
    $result = $sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
    
    add2log(3,"/v1/sensorunit/move2customer: Moved serialnumber:$serialnumber to customer:$customernumber");# info
    return { message => "OK" };
};
	
# sensor data handling
# data is in the for as will be written to the filesystem for picking up as UUCP
# {"payloadversion":"1","serialnumber":"21-1001-AA-00266","timestamp":"timestamp","packagecounter":"2522","sensordata":"13.88,66.08,4.59,1.00,-68"}
# 
post '/v1/sensordata/add' => sub {
  # Check if missing parameter
	if (not params->{serialnumber} or not params->{sensordata}){
		send_error("Missing parameter: needs serialnumber and sensordata");
	}
	if (!authorized('/v1/command',params->{serialnumber})){
		send_error("You are not authorized to access this record",500);
	}
	my $serialnumber=params->{serialnumber};
	my $payloadversion=params->{payloadversion} || 0;
	my $timestamp=params->{timestamp} || time();
	my $packagecounter=params->{packagecounter} || 0;	
	my $sensordata=params->{sensordata};
	# sensordata: 1677899383, 21-1003-AB-00026, 3.97, 97.36, 1005.00, 3.00, 0.01, 0.94, 0.00, -22.00, 1
	# tags      : <epoc>,<serialnumber>,<sensorvalue>,,,<packagenumber>
	my $combined="$timestamp,$serialnumber,$sensordata,$packagecounter";

	my $filename=makeuniquefilename("$uucppath$serialnumber",'aa');
	open OUTFILE, '>', "$filename";
	binmode OUTFILE;
	print OUTFILE $combined;
	close OUTFILE;
	add2log(4,"Added sensordata to incomming queue with data: $combined");# debug
	return{result =>"OK"};
};
	
#
#<value><upper_threshold><lower_threshold><serialnumber><sensorname><productname><unittype><unittypedescription>
# Event handler. Need serialnumber and event number. option user.
# params: serialnumber, event, option username,userid
post '/v1/event/add' =>sub {
	if (not params->{serialnumber} or not params->{event} ){
		send_error("Missing parameter, needs serialnumber and event with option username/userid",400);
  }
  my $event = params->{event};
  my $username = params->{username} || '';
  my $userid = params->{userid} || '';
  
  open(MAIL, "|/usr/sbin/sendmail -t");
	# Email Header
	print MAIL "To: kjell\@sundby.com\n";
	print MAIL "From: portal.7sense.no\n";
	print MAIL "Subject: eventnumber=$event\n\n";
		# Email Body
	print MAIL "eventnumber=$event";
	close MAIL;  
  
  return {message =>"OK"};
  # Fetch message all languages
	my $sth = $mainbase_db_ctl->prepare("SELECT customers_id_ref,irrigation_sms,irrigation_email from message_templates where message_number=event");
  $sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
  my @message_dataset=();
	while (my $row=$sth->fetchrow_hashref()){
		push (@message_dataset,$row);
	}
	$sth->finish();
	#
  
  # Find users that shall receive the event message
  my $sensorunits_id=0;
 $sth = $mainbase_db_ctl->prepare("SELECT customers_id_ref,irrigation_sms,irrigation_email from message_users inner join users on user_id=users_id_ref where sensorunits_id_ref=$sensorunits_id");
  $sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
  my @dataset=();
  while (my $row=$sth->fetchrow_hashref()){
  	push (@dataset,$row);
  }
  $sth->finish();
  
  # Find owner of sensor
  $sth = $mainbase_db_ctl->prepare("SELECT customers_id_ref,irrigation_sms,irrigation_email from sensorunits inner join customer on customer_id=customer_id_ref where serialnumber='$serialnumber'");
  $sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
  my $row=$sth->fetchrow_hashref();
  my $irrigation_sms=$row->{'irrigation_sms'};
  my $irrigation_email=$row->{'irrigation_email'};
  $sth->finish();
  return {message =>"OK"};
};
# Send sms
post '/v1/sendsms' =>sub {
	if (not params->{mobilnumber} or not params->{text} ){
		send_error("Missing parameter, needs mobilnumber and text",400);
  }
  my $mobilnumber = params->{mobilnumber};
  my $text = params->{text};
		
		# Remove space and -
		$mobilnumber =~ tr/ |\-//ds;
		add2log(4," SMS: to:$mobilnumber text:$text");
		my $content = '{"source": "'."7sense".'","destination": "'.$mobilnumber.'","userData": "'.$text.'","platformId": "COMMON_API","platformPartnerId": "12979","deliveryReportGates":["uWkvChSX"],"useDeliveryReport": true,"refId":"'.$mobilnumber.'"}';
		my $reply=`curl -sS --data '$content' --header 'Content-Type: application/json' --header 'Authorization: Basic V3N6aDVmdlQ6TUMyaGc4Nm4=' --header 'charset=utf-8' --header 'User-Agent: curl/7.26.0' https://wsx.sp247.net/sms/send`;
		
		add2log(4," SMS reply: $reply");
		if ($reply eq ''){
			add2log(1," Error sending SMS: to:$mobilnumber:text:$text, reply:$reply");
			send_error("Error sending SMS: to:$mobilnumber:text:$text, reply:$reply",400);
		}
		my $replyhash=decode_json($reply);
		if ($replyhash->{'resultCode'} ne '1005'){
				add2log(1," Error sending SMS: to:$mobilnumber:text:$text, reply:$reply");
		}
};
# SMS message to user(s) based on serialnumber or sensorsunit_id or user_id
post '/v1/sendmessage' =>sub{
	if (not params->{serialnumber} and not params->{sensorunit_id} and not params->{user_id}){
		send_error("Missing parameter, needs serialnumber or sensorunit_id or user_id. Option mailmessage, mailsubject, smsmessage, pushmessage",400);
  }
  my $serialnumber = params->{serialnumber} || '';
  my $sensorunit_id = params->{sensorunit_id} || '';
  my $user_id = params->{user_id} || '';
  my $mailmessage = params->{mailmessage};
  my $mailsubject = params->{mailsubject} || 'Message from 7sense';
  my $smsmessage = params->{smsmessage};
  my $pushmessage = params->{pushmessage};
    
  #utf8::encode($message);
  #add2log(4,"message:$message");
	#utf8::encode($message);
	
	# Find sensorunits_id based on serialnumber
	if ($serialnumber) {
		my $sth = $mainbase_db_ctl->prepare( "SELECT sensorunit_id FROM sensorunits where serialnumber='$serialnumber'");
		my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
		my $rows=$sth->fetchrow_hashref();
		$sth->finish();
		
		# if not found return error
		if ($result eq "0E0"){
			add2log(1,"sendmessage: Serialnumber $serialnumber is missing in DB");
			send_error("Serialnumber $serialnumber is missing inDB",400);
		}
		# Get sensor id
		$sensorunit_id= trim($rows->{'sensorunit_id'});
	} 
	# If no user_id, get users_id for people that we will send push to phone
	my @dataset=();
	if (not $user_id){
		my $sth = $mainbase_db_ctl->prepare("SELECT users_id_ref,sms,email,push_notification FROM message_receivers where sensorunits_id_ref=$sensorunit_id and (sms=TRUE or email=TRUE or push_notification=TRUE)");
		my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
		while (my $row=$sth->fetchrow_hashref()){
			push (@dataset,$row);
		}
		$sth->finish();
	}else{
		# If user_id was a paramerter get data for him.
		#my $sth = $mainbase_db_ctl->prepare( "SELECT users_id_ref,sms,email,push_notification FROM message_receivers where sensorunits_id_ref=$sensorunit_id and user_id_ref=$user_id and (sms=TRUE or email=TRUE or push_notification=TRUE");
		#my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
		#while (my $row=$sth->fetchrow_hashref()){
		#	push (@dataset,$row);
		#}
		# $sth->finish();
		# Set flags to true. Content of mailmessage, smsmessage,pushmessage will deside type of message to send
		@dataset[0]={'users_id_ref'=>$user_id,'email'=>1,'sms'=>1,'push_notification'=>1};
	}
	#add2log(4,Dumper(@dataset));
	# Get user attributes and send
	foreach my $user_id_hash (@dataset){
		# Get user id and what transport message should to user on
		my $user_id=$user_id_hash->{users_id_ref};
		my $mail_receiver=$user_id_hash->{email};
		my $sms_receiver=$user_id_hash->{sms};
		my $push_receiver=$user_id_hash->{push_notification};
		# Get email and mobilnumber for user
		my $sth = $mainbase_db_ctl->prepare( "SELECT user_email,user_phone_work FROM users where user_id=$user_id");
		my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
		my $rows=$sth->fetchrow_hashref();
		$sth->finish();
		# if not found return error
		if ($result eq "0E0"){
			add2log(1,"sendmessage: user id  $user_id is missing");
			send_error("User id  $user_id is missing",400);
		}
		# Get email and phone
		my $user_phone_work= trim($rows->{'user_phone_work'}) || '';
		my $user_email= trim($rows->{'user_email'}) || '';
		#
		# send email, sms and push if needed
		if ($mail_receiver and $user_email and $mailmessage){
			$mailmessage=~ s/<br>/\n/g;
			$mailmessage="$mailmessage\n\nBest regards,\n7Sense Support";
			my $msg = MIME::Lite->new(From=>'no-reply@7sense.no',To=>$user_email,Subject=>$mailsubject,Data=>$mailmessage);
			$msg->send;
			add2log(3,"sendmessage: Mail sent to $user_email with subject $mailsubject");
		}
		#	 
		if ($sms_receiver and $user_phone_work and $smsmessage){
			$user_phone_work =~ tr/ |\-//ds;
			$smsmessage=~ s/\n/ /g;
			$smsmessage="$smsmessage Best regards, 7Sense Support";
			add2log(4,"sendmessage: SMS to $user_phone_work message $smsmessage");
			#my $json_string = '{"source": "'."7sense".'","destination": "'.$user_phone_work.'","userData": "'.'$message'.'","platformId": "COMMON_API","platformPartnerId": "12979","deliveryReportGates":["uWkvChSX"],"useDeliveryReport": true,"refId":"'.$user_phone_work.'"}';
			my $json_string = "{'source': '7sense','destination':'$user_phone_work','userData':'$smsmessage','platformId':'COMMON_API','platformPartnerId': '12979','deliveryReportGates':['uWkvChSX'],'useDeliveryReport': true,'refId':'$user_phone_work'}";
			# convert ' to "
			$json_string=~s/'/"/g;
			add2log(4,"sendmessage: json_string $json_string");
			my $response=`curl -sS --data '$json_string' --header 'Content-Type: application/json' --header 'Authorization: Basic V3N6aDVmdlQ6TUMyaGc4Nm4=' --header 'charset=utf-8' --header 'User-Agent: curl/7.26.0' https://wsx.sp247.net/sms/send`;
			#my $response=api_command("https://exp.host/--/api/v2/push/send",'POST',$json_string,'[Authorization=>Basic V3N6aDVmdlQ6TUMyaGc4Nm4=]');
			add2log(4,"sendmessage: SMS reply: $response");
			if ($response eq ''){
				add2log(1,"sendmessage: Error sending SMS: to:$user_phone_work:text:$smsmessage, reply:$response");
				send_error("Error sending SMS: to:$user_phone_work:text:$smsmessage, reply:$response",400);
			}
			my $replyhash=decode_json($response);
			if ($replyhash->{'resultCode'} ne '1005'){
					add2log(1,"sendmessage: Error sending SMS: to:$user_phone_work:text:$smsmessage, reply:$response");
			}
		}
		#
		if ($push_receiver and $pushmessage){
			# Get user mobil number
			my $badge=get_user_variable($user_id,'pushbadge') || 0;
			my $pushsound=get_user_variable($user_id,'pushsound') || 'notification.wav';
			my $pushtoken=get_user_variable($user_id,'pushtoken') || '';
			# Check if token is set for user
			if (not $pushtoken){
				add2log(0,"sendmessage: Token missing for userid: $user_id");
				next;
			}
			# Inc badge number with 1
			$badge=$badge+1;
			utf8::encode($pushmessage);
			$pushmessage=~s/\n/ /g;
			# Build JSON
			my $json_string="{'to':'$pushtoken','title':'Message from 7Sense','body':'$pushmessage','channelId':'default','sound':'$pushsound','badge':'$badge'}";
			# convert ' to "
			$json_string=~s/'/"/g;
			add2log(3,"sendmessage: Push sent JSON: $json_string to user_id $user_id");
			# Send push to phone via exp api
			my $response=api_command("https://exp.host/--/api/v2/push/send",'POST',$json_string,'');
			#print $response->{'data'}->{'status'};print "\n";
			if ($response){
				add2log(4,"sendmessage: Push response from exp API for user_id: $user_id: ".$response->{'data'}->{'status'});
				if ($response->{'data'}->{'status'} eq "error"){
					add2log(0,"sendmessage: Push error from exp API for user_id: $user_id :".$response->{'data'}->{'message'});
				}
			}else{
				add2log(0,"sendmessage: Push no response from EXP API for user_id: $user_id");
			}
			# Store badge number
			update_user_variable($user_id,'pushbadge',$badge);
		}
	}
	return {result =>"OK", messages=>scalar(@dataset)};
};

#
# PUSH message to user based on serialnumber or sensorsunit_id or user_id
#
post '/v1/pushmessage' =>sub{
	if (not params->{serialnumber} and not params->{sensorunit_id} and not params->{user_id} or not params->{message}  ){
		send_error("Missing parameter, needs message and (serialnumber or sensorunit_id or user_id) with option subject",400);
  }
  my $serialnumber = params->{serialnumber} || '';
  my $sensorunit_id = params->{sensorunit_id} || '';
  my $user_id = params->{user_id} || '';
  my $message = params->{message};
  my $subject = params->{subject} || 'Message from 7sense';
  utf8::encode($message);
	
	# Find sensorunits_id based on serialnumber
	if ($serialnumber) {
		my $sth = $mainbase_db_ctl->prepare( "SELECT sensorunit_id FROM sensorunits where serialnumber='$serialnumber'");
		my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
		my $rows=$sth->fetchrow_hashref();
		$sth->finish();
		
		# if not found return error
		if ($result eq "0E0"){
			add2log(1,"pushmessage: Serialnumber $serialnumber is missing");
			send_error("Serialnumber $serialnumber is missing",400);
		}
		# Get sensor id
		$sensorunit_id= trim($rows->{'sensorunit_id'});
	}
	#
	# 
	# If no user_id, get users_id for people that we will send push to phone
	my @dataset=();
	if (not $user_id){
		my $sth = $mainbase_db_ctl->prepare( "SELECT users_id_ref FROM message_receivers where sensorunits_id_ref=$sensorunit_id and push_notification=TRUE");
		my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
		while (my $row=$sth->fetchrow_hashref()){
			push (@dataset,$row);
		}
		$sth->finish();
	}else{
		@dataset[0]={'users_id_ref'=>$user_id};
	}
	# Get user attributes and send
	foreach my $user_id_hash (@dataset){
		my $user_id=$user_id_hash->{users_id_ref};
		#my $user_id=456;
		# Get user variables
		my $badge=get_user_variable($user_id,'pushbagde') || 0;
		my $pushsound=get_user_variable($user_id,'pushsound') || 'notification.wav';
		my $pushtoken=get_user_variable($user_id,'pushtoken') || '';
		# Check if token is set for user
		if (not $pushtoken){
			add2log(0,"pushmessage: Token missing for userid: $user_id");
			next;
		}
		# Inc badge number with 1
		$badge=$badge+1;
		# Build JSON
		my $json_string="{'to':'$pushtoken','title':'$subject','body':'$message','channelId':'$pushsound','sound':'$pushsound','badge':'$badge'}";
		# convert ' to "
		$json_string=~s/'/"/g;
		add2log(3,"pushmessage: Sent JSON: $json_string to user_id $user_id");
		# Send push to phone via exp api
		my $response=api_command("https://exp.host/--/api/v2/push/send",'POST',$json_string,'');
		#print $response->{'data'}->{'status'};print "\n";
		if ($response){
			add2log(4,"Response from exp API for user_id: $user_id: ".$response->{'data'}->{'status'});
			if ($response->{'data'}->{'status'} eq "error"){
				add2log(0,"Error from exp API for user_id: $user_id :".$response->{'data'}->{'message'});
			}
		}else{
			add2log(0,"No response from EXP API for user_id: $user_id");
		}
		# Store badge number
		update_user_variable($user_id,'pushbadge',$badge);
	}
	return {result =>"OK", messages=>scalar(@dataset)};
};

#
#
# Turn output on/off
#
# serialnumber,output number
# sensor_variables in use
# remotecontroller_status 0=not used, 1=Started, 2=Stopped, 3=Waiting for reply to start, 4=Waiting for reply to stop, 5=Error x88pumpcontroller_reply holds reason
# remotecontroller_reply = reply text from Onomondo
# remotecontroller_phonenumber = Senders SIM ID
patch '/v1/sensorunit/ports/output/on' =>sub {
	if (not params->{serialnumber} or not params->{port} ){
		send_error("Missing parameter, needs serialnumber and port",400);
  }
  my $serialnumber = params->{serialnumber};
  my $port = params->{port};
  # Get phonenumber
  my $remotecontroller_phonenumber=dbget_variable($serialnumber,'sensorunit_variables','remotecontroller_phonenumber');
  if (not $remotecontroller_phonenumber){
  	send_error("Missing remotecontroller_phonenumber or empty",400);
  }
  my $reply='';
  if ($serialnumber eq "23-1005-AA-00001"){
  	$reply=send_sms_with_linkmobility($remotecontroller_phonenumber,"41716208","Start $port");
  }else{
  	$reply=send_sms_with_linkmobility($remotecontroller_phonenumber,"+4741716208","Start $port");
  }

  # Update status
  my $updated_at=time();
  my $remotecontroller_status=dbget_variable($serialnumber,'sensorunit_variables','remotecontroller_status') || "2,1731988046,2,1730988016";
  my @status_list=split(',',$remotecontroller_status);
  
  if ($port eq 1){$remotecontroller_status="3,$updated_at,$status_list[2],$status_list[3]"}
  else{$remotecontroller_status="$status_list[0],$status_list[1],3,$updated_at"}
  dbupdate_variable($serialnumber,'sensorunit_variables','remotecontroller_status');

  add2log(4,"$serialnumber: Sent activated port $port to $remotecontroller_phonenumber");
  return{result =>"$reply"};
};
patch '/v1/sensorunit/ports/output/off' =>sub {
	if (not params->{serialnumber} or not params->{port} ){
		send_error("Missing parameter, needs serialnumber and port",400);
  }
 	my $serialnumber = params->{serialnumber};
  my $port = params->{port};
  # Get phonenumber
  my $remotecontroller_phonenumber=dbget_variable($serialnumber,'sensorunit_variables','remotecontroller_phonenumber');
  if (not $remotecontroller_phonenumber){
  	send_error("Missing remotecontroller_phonenumber or empty",400);
  }
  my $reply='';
  if ($serialnumber eq "23-1005-AA-00001"){
  	$reply=send_sms_with_linkmobility($remotecontroller_phonenumber,"41716208","Stop $port");
  }else{
  	$reply=send_sms_with_linkmobility($remotecontroller_phonenumber,"+4741716208","Stop $port");
  }

  # Update status
  my $updated_at=time();
  my $remotecontroller_status=dbget_variable($serialnumber,'sensorunit_variables','remotecontroller_status') || "2,1731988046,2,1730988016";
  my @status_list=split(',',$remotecontroller_status);
  
  if ($port eq 1){$remotecontroller_status="4,$updated_at,$status_list[2],$status_list[3]"}
  else{$remotecontroller_status="$status_list[0],$status_list[1],4,$updated_at"}
  dbupdate_variable($serialnumber,'sensorunit_variables','remotecontroller_status');
  
  add2log(4,"$serialnumber: Sent activated port $port to $remotecontroller_phonenumber");
  return{result =>"$reply"};
};
# 23-1005-AA-00001
get  '/v1/sensorunit/ports/output/status' =>sub {
	if (not params->{serialnumber}){
		send_error("Missing parameter, needs serialnumber",400);
  }
 	my $serialnumber = params->{serialnumber};

	# Get number
  my $remotecontroller_config=dbget_variable($serialnumber,'sensorunit_variables','remotecontroller_config') || "2,1,1";
  my ($port_numbers,@activated)=split(',',$remotecontroller_config);
  my $remotecontroller_status=dbget_variable($serialnumber,'sensorunit_variables','remotecontroller_status') || "2,1731988046,1,1730988016";
  my $remotecontroller_reply=dbget_variable($serialnumber,'sensorunit_variables','remotecontroller_reply') || "No message";
  my @remotecontroller_status_array=split(',',$remotecontroller_status);
  # Build hash
  my @return_data=();
  my $portnumber=1; # Array start on 0, portnumber start on 1
  foreach my $state (@activated){
  	if ($state) {
  		my $status=$remotecontroller_status_array[($portnumber-1)*2];
  		my $updated_at=$remotecontroller_status_array[($portnumber-1)*2+1];
  		push @return_data, {port => "$portnumber", status => "$status", updated_at => "$updated_at"};
  	}
  	$portnumber ++;
  }
  
  #return "[{output => 1,status =>"1", updated_at => "12312313",message=>"Pumpe 1 startet"},{output => 1,status =>"1", updated_at => "12312313",message=>"Pumpe 2 stopped"}]";
  #my @return_data = ({port => "1",status =>"1", updated_at => "1730981046",message=>"Pumpe 1 startet"},{port => "2",status =>"2", updated_at => "1731988046",message=>"Pumpe 2 stopped"},{port => "3",status =>"5", updated_at => "1730988016",message=>"Pumpe 3 startet"},{output => "4",status =>"0", updated_at => "1630988046",message=>"Pumpe 4 stopped"});
  send_as JSON => \@return_data;
};


# Start Dance2
dance;


# Get user variables
sub get_user_variable{
	my ($user_id,$variable)=@_;
	# Get current value
	my $sth = $mainbase_db_ctl->prepare( "SELECT value FROM user_variables where user_id=$user_id and variable='$variable'");
	my $result=$sth->execute(); 
	my $rows=$sth->fetchrow_hashref();
	$sth->finish();
	# if not found return empty
	if ($result eq "0E0"){return ''}
	# Return value
	return trim($rows->{'value'});
}
sub update_user_variable{
	my  ($user_id,$variable,$value)=@_;
	# Update variable with new value
	my $sth = $mainbase_db_ctl->prepare( "UPDATE user_variables set value='$value', updated_at=current_timestamp where user_id=$user_id and variable='$variable'");
	my $result=$sth->execute();
	$sth->finish();
	# if not found create the variable
	if ($result eq "0E0"){
		$sth = $mainbase_db_ctl->prepare( "INSERT INTO user_variables (serialnumber,variable,value,updated_at) VALUES ('$serialnumber','$variable','$value',current_timestamp)");
		$sth->execute();
		add2log(2,"$serialnumber: Missing variable: $variable  for serialnumber: $serialnumber. Created");# Info
	}
	return 1;
}

#
# Update usage record with new value
#
sub dbget_variable{
	my ($serialnumber,$dbtable, $variable)=@_;
	# Get current value
	my $sth = $mainbase_db_ctl->prepare( "SELECT value FROM $dbtable where serialnumber='$serialnumber' and variable='$variable'");
	my $result=$sth->execute(); 
	my $rows=$sth->fetchrow_hashref();
	$sth->finish();
	
	# if not found return empty
	if ($result eq "0E0"){return ''}
	# Return value
	return trim($rows->{'value'});
}
sub dbupdate_variable{
	my  ($serialnumber,$dbtable, $variable,$value)=@_;
	# Update variable with new value
	my $sth = $mainbase_db_ctl->prepare( "UPDATE $dbtable set value='$value', updated_at=current_timestamp where serialnumber='$serialnumber' and variable='$variable'");
	my $result=$sth->execute();
	$sth->finish();
	# if not found create the variable
	if ($result eq "0E0"){
		$sth = $mainbase_db_ctl->prepare( "INSERT INTO $dbtable (serialnumber,variable,value,updated_at) VALUES ('$serialnumber','$variable','$value',current_timestamp)");
		$sth->execute();
		$sth->finish();
		add2log(2,"$serialnumber: Missing variable: $variable  for serialnumber: $serialnumber. Created");# Info
	}
	return 1;
}


# Check i allowd to change 
sub allowed2change{
	my ($user_id,$serialnumber)=@_;
	my $sth = $mainbase_db_ctl->prepare("SELECT changeallowed FROM sensoraccess WHERE user_id=$user_id and serialnumber='$serialnumber'");
	my $result=$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	# If not exits return empty
 if ($result eq "0E0"){
        return '';
  }
	my $row=$sth->fetchrow_hashref();
	my $changeallowed=$row->{changeallowed};
	$sth->finish();
	add2log(4,"changeallowed:$changeallowed user_id $serialnumber");# debug
	return $changeallowed;
}

#  Authorized
sub authorized {
	return 1;	
	my ($url,$serialnumber,)=@_;
	my ($auth_type, $authtoken) = split(' ',request_header 'Authorization');
	my $uri=request->to_string;
	my $ipaddress=request->remote_address;

	
	add2log(4,"auth:$auth_type, $authtoken,$uri,$ipaddress");
	if ($ipaddress eq '127.0.0.0' or $ipaddress eq "localhost"){
		# local host is accessing. Approved
		return 1;
	}
	my $productnumber=substr($serialnumber,0,7);

	# Search database for access rights
	my $sth = $mainbase_db_ctl->prepare( "SELECT authtoken FROM apiauthorization WHERE productnumber ='$productnumber'");
	$sth->execute() or die "Can't execute SQL statement: $DBI::errstr\n";
	my @dataset=$sth->fetchrow_array();
	$sth->finish();
	my $key=trim($dataset[0]);
	if ($authtoken eq $key){return 1;}
	
	return 0;
}
# get user_id from token
sub get_userid_from_token {
	# Get token from header
	my ($auth_type, $authtoken) = split(' ',request_header 'Authorization');
	add2log(4,"auth_token:$authtoken");# debug
	# Dummy until made a table
	if ($authtoken eq "x31cnsnOa7SzJcnEL2ZH5tAoWgiKioU8"){return 296;}# Horten kommune
	if ($authtoken eq "BWO7FflcUyQX3mUnMgUoROZ6VwBgaFW4"){return 300;}# Atea
	if ($authtoken eq "ej95CCJstx1GgyloOj209IopGpX12RbE"){return 301;}# Maltevinje
	if ($authtoken eq "sdfgk349gmn29vmna93rnrf9aa3bhpl4"){return 503;}# Maltevinje
	if ($authtoken eq "ysD34CIsInR5cCI6IkpXVCIsImtpZCI6"){return;}
	if ($authtoken eq "asdfmjrtaADFG348RKVvnsarguja7df0"){return 512;} # harald@agilkompetanse.no 15.aug.2024
	if ($authtoken eq "xcblawaerg034ttgaw24lr3fgggplsfm"){return 291;} # ma@datavaxt.se 15.aug.2024
	if ($authtoken eq "klaegnavuefnveeawEFJH458aertuwt"){return 499;} # anne@linnes.no 10 des 2024
	if ($authtoken eq "SDFGK54sdfgmnagj48naarj3jkfkang"){return 356;} # fredrik@soilmate.no 10 des 2024
	if ($authtoken eq "KmioserhmLKmgke834k59KghmKokdhs"){return 218;} # Fjellhagebruk 27 jan 2025
	return -1
}
# get access right for token
sub access_via_token {
	my ($serialnumber)=@_;
	# Get user ID from token
	my $user_id=get_userid_from_token() || '';
	add2log(4,"get_userid_from_token:$user_id");# debug
	if (not defined $user_id or $user_id eq ''){return 'W'}# Full access
	if ($user_id eq -1){return}; # No access
	# search access list for access right
	my $accessright=allowed2change($user_id,$serialnumber);
	add2log(4,"accessright:$accessright:$serialnumber");# debug
	if ($accessright eq '0'){$accessright='R'}
	if ($accessright eq '1'){$accessright='W'}
	return $accessright;
}

# make unique fimes name.
# Check if suggested is in use and tries another.
sub makeuniquefilename {
	my ($filename,$type)=@_;
	my $newfilename="$filename.$type";
	while (-e $newfilename){
		$newfilename=$filename."_".int(rand(10000)).".$type";
	}
	return $newfilename;
}


   
# Trim leading and ending white space and remove tab/return
sub trim {
	if (!$_[0]){return $_[0]}
   (my $s = $_[0]) =~ s/^\s+|\s+$|[\n\t]//g;
   #$s=~ s/\n+//g;
   return $s;       
}

# log messages
# Text, level
# add2log("Deamon started",4)
sub add2log{
	my ($severity,$message)=@_;
	my @severitytext=("FATAL","ERROR","WARN","INFO","DEBUG","TRACE");
	 # Open log file
	binmode(STDOUT, ":utf8");
	open LOGFILE, ">>$logfile" or die "cannot open file $logfile: $!";
	LOGFILE->autoflush(1); # No buffer
	
	# make nice log time
	my $logtime=localtime(time)->strftime('%F %T');
	print LOGFILE "$logtime $severity $severitytext[$severity] $message\n";
	# Check if we should send this legmessage
	if ($sendinfolevel >= $severity){
		open(MAIL, "|/usr/sbin/sendmail -t");
		# Email Header
		print MAIL "To: $errorreceivers\n";
		print MAIL "From: $hostname\n";
		print MAIL "Subject: $severitytext[$severity] from $hostname\n\n";
		# Email Body
		print MAIL "$logtime $severity $severitytext[$severity] $message";
		close MAIL;
	}
	close LOGFILE;
	return;
}

sub api_command{
	my ($url,$method,$json_data,$header)=@_;
	#$header = ['Authorization' => "Bearer $auth_token", 'Content-Type' => 'application/json; charset=UTF-8'];
	$header=[];
	my $request = HTTP::Request->new($method => "$url", $header, $json_data);
	$request->header(Content_Type => 'application/json;charset=utf-8');
	my $ua = LWP::UserAgent->new('ssl_opt' => 0); # You might want some options here
	my $response = $ua->request($request);
	my $json_hash=[];
	eval {$json_hash=decode_json($response->content)};
	#print Dumper($json_hash);
	
	# If fails return empty
	if ($@) {return};
	return $json_hash;
}

# POST TO API
sub send_sms_with_onomondo_api{
	my ($phonenumber,$text)=@_;
	my $url="https://api.onomondo.com/sms/$phonenumber";
	#my $url="http://development.portal.7sense.no:6000/sms/$phonenumber";
	my $req = HTTP::Request->new(POST => $url);
	$req->content_type('application/json');
	$req->header('Authorization' => 'onok_f0b4c956.RLoCA/w6l3imtU7KOJovj/bvwfzaJ2xmzU1CHfJmdJj0RFtwTCAj9/hp');
	my $json_string="{'from':'+4733084400','text':'$text'}";$json_string=~s/'/"/g;
	$req->content($json_string);

	my $ua = LWP::UserAgent->new('ssl_opt' => 0); # You might want some options here
	my $result = $ua->request($req);
	my $message='';
	if ($result->is_success) {
  	$message = $result->decoded_content;
	}
	else {
    add2log(2,"$phonenumber: HTTP POST error code: ".$result->code."n HTTP POST error message: ".$result->message."n");
	  return $result->message;
	}
	add2log(4,"$phonenumber: HTTP POST code: ".$result->code."n HTTP POST message: ".$result->message."n");
	return $result->message;
}

# Send sms with linkmobility
sub send_sms_with_linkmobility{
	my ($mobilnumber,$sendernumber,$text)=@_;
		
		# Remove space and -
		$mobilnumber =~ tr/ |\-//ds;
		add2log(4," SMS: to:$mobilnumber text:$text");
		my $content = '{"source": "'."$sendernumber".'","destination": "'.$mobilnumber.'","userData": "'.$text.'","platformId": "COMMON_API","platformPartnerId": "12979","deliveryReportGates":["uWkvChSX"],"useDeliveryReport": true,"refId":"'.$mobilnumber.'"}';
		my $reply=`curl -sS --data '$content' --header 'Content-Type: application/json' --header 'Authorization: Basic V3N6aDVmdlQ6TUMyaGc4Nm4=' --header 'charset=utf-8' --header 'User-Agent: curl/7.26.0' https://wsx.sp247.net/sms/send`;
		
		add2log(4," SMS reply: $reply");
		if ($reply eq ''){
			add2log(1," Error sending SMS: to:$mobilnumber:text:$text, reply:$reply");
			send_error("Missing parameter, needs mobilnumber and text",400);
		}
		my $replyhash=decode_json($reply);
		if ($replyhash->{'resultCode'} ne '1005'){
				add2log(1," Error sending SMS: to:$mobilnumber:text:$text, reply:$reply");
		}
		return  $reply;
}
