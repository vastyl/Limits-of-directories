#!/usr/bin/perl -w

#########################################################################
### Limits of directories for webmail                                                
###                                                                     
### Copyright (C) 2014 Stanislav Vastyl (stanislav@vastyl.cz)
###
### This program is free software: you can redistribute it and/or modify
### it under the terms of the GNU General Public License as published by
### the Free Software Foundation, either version 3 of the License, or
### any later version.
###
### This program is distributed in the hope that it will be useful,
### but WITHOUT ANY WARRANTY; without even the implied warranty of
### MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
### GNU General Public License for more details.
###
### You should have received a copy of the GNU General Public License
### along with this program. If not, see <http://www.gnu.org/licenses/>.
#########################################################################

use strict;
use warnings;
use Switch;
use DBI;
use POSIX;
use Mail::SendEasy;
use Data::Dumper;

	
### unit is Mbs
our $DATA_LIMIT = 1500;
our $DB_LIMIT = 500;

### path
our $ROOT_PATH="/srv";
our $WEB_PATH=$ROOT_PATH."/www";

### config path
our $CONFIG_PATH = "/etc/httpd/conf/virtuals/";

### mail settings
our $mail = new Mail::SendEasy(
smtp => 'localhost' ,
#user => 'foo' ,
#pass => 123 ,
) ;

### connect of databases
my $dbh = DBI->connect("DBI:mysql:limitsdir:localhost","xxxx","xxxxxxxxxxx") or die "Connection Error: $DBI::errstr\n";
our @row;

opendir (DH, $WEB_PATH)or die "couldn open derictory: $!\n";
my @foldername = grep ! /^\./, readdir DH;
closedir (DH);

### lists of folders and update db
###
###columns in db: 
###status0-OK,1-notice,2-warning,3-error,4-fatalError
###exception:0-no,1-yes
###blocked:0-no,1-yes
###
foreach my $name (@foldername) {
	###db size
	my $smallName;
	my $l_length;
	my $first = split (/\./, $name);
	$l_length = length($first);
	if ($l_length < 5) {$smallName = substr($name,0,4); }
	elsif ($l_length > 5) {$smallName = substr($name,0,6); }
	my $db_sql = "SELECT SUM(data_length + index_length) / 1024 / 1024 FROM information_schema.TABLES where table_schema LIKE \"$smallName%\"  GROUP BY table_schema limit 1;";
#	my $sth_db = $dbh->prepare($db_sql);
	my $db_size = $dbh->selectrow_array($db_sql);
#	$db_size = int($db_size);
	$db_size = ceil($db_size);

	###folder size
	my $all_path="$WEB_PATH/$name";
	my $web_size=getDirSize($all_path);
	$web_size = int($web_size);
	
	###write informations
	print "Host: ". $name ."\nSize: ". $web_size ."MB\nDB: ". $db_size ."MB\n";	
	my $insert = "INSERT INTO list (name,web_size,db_size,exception,blocked,status,date) VALUES ('$name',$web_size,$db_size,0,0,0,NOW()) ON DUPLICATE KEY UPDATE name='".$name."', web_size=".$web_size.", db_size=".$db_size.";";
	my $sth = $dbh->prepare($insert);
	$sth->execute or die "SQL Error: $DBI::errstr\n";
	print "\n----------SAVE/UPGRADE-----------\n";
}

## main function 
my $sth_sql = $dbh->prepare('select * from list where exception = 0;');
$sth_sql->execute or die "SQL Error: $DBI::errstr\n";
while (@row = $sth_sql->fetchrow_array) {

	my $size = ($row[1]+$row[2]);
	
	##switch
	switch ($size) {
		 case { $size <= ($DATA_LIMIT-500) } {status_ok($row[0]);}
		 case { ($size > ($DATA_LIMIT-500)) && ($size <= ($DATA_LIMIT-100))} {phase_one($row[0]);}
		 case { ($size > ($DATA_LIMIT-99)) && ($size <= ($DATA_LIMIT-10))} {phase_two($row[0],$row[6]);}
		 case { ($size > ($DATA_LIMIT-9)) && ($size <= $DATA_LIMIT)} {phase_three($row[0],$row[6]);}
		 case { $size >= $DATA_LIMIT } {phase_four($row[0],$row[6]);}
	}
	print "\n";
}


#####################################################
##################SUBROUTINES#######################
#####################################################

sub getDirSize() {
	
my $path = shift;
my $sizes = `du -sm $path`;
my $total = 0;

for(split /[\r\n]+/,$sizes) # split on one or more newline characters
{ 
	my($number,$file) = split /\t/,$_,2; # split on tab ($file not used here)
	$total += $number; 
}
return $total;
}

sub status_ok(){
my $ok_sql = "UPDATE list SET status = 0 WHERE name = \"".$_[0]."\";";
my $sth_ok = $dbh->prepare($ok_sql);
$sth_ok->execute;
return print "Webhosting $_[0] - Status: OK!" # <1000Mb
}

sub phase_one(){
my $notice_sql = "UPDATE list SET status = 1 WHERE name = \"".$_[0]."\";";
my $sth_notice = $dbh->prepare($notice_sql);
$sth_notice->execute;
return print "Webhosting $_[0] - Status: Notice!"; # >1000Mb<1400Mb
}

sub phase_two(){
my $date30 = strftime "%Y-%m-%d",localtime(time +30 * 24 * 60 * 60);
my $date = strftime "%Y-%m-%d", localtime;
	if ($_[1] ge $date30)
#	if ($_[1] le $date) # pro test
	{
        ###find email
        my $email = `grep "# LDAP login:" -ri $CONFIG_PATH$_[0].conf`;
        $email=~ s/ //g;
        $email=~ s/#LDAPlogin://gi;
                                                               
		my $warning_sql = "UPDATE list SET status = 2, date=NOW() WHERE name =\"".$_[0]."\" ";
		my $sth_warning = $dbh->prepare($warning_sql);
		$sth_warning->execute;
		my $status = $mail->send(
 		from    => 'xxxx' ,
		to      => '$email' ,
		subject => "INFORMACNI EMAIL" ,
		msg     => "Vas webhosting $_[0] se blizi k horni hranici weboveho prostoru! Prosim, dbejte zvysenou obezretnost velikosti abychom predesli pripadne blokaci." ,
		) ;
		if (!$status) { print $mail->error ;}
	}
	else
	{
		my $warning_sql = "UPDATE list SET status = 2 WHERE name = \"".$_[0]."\";";
		my $sth_warning = $dbh->prepare($warning_sql);
		$sth_warning->execute;
	}
	return print "Webhosting $_[0] - Status: Warning!"; # >1400Mb<1490Mb
}

sub phase_three(){

my $date1 = strftime "%Y-%m-%d",localtime(time +1 * 24 * 60 * 60);
my $date = strftime "%Y-%m-%d", localtime;
	if ($_[1] gt $date1)
#	if ($_[1] le $date) # pro test
	{
        ###find email
        my $email = `grep "# LDAP login:" -ri $CONFIG_PATH$_[0].conf`;
        $email=~ s/ //g;
        $email=~ s/#LDAPlogin://gi;
	
		my $error_sql = "UPDATE list SET status = 3, date=NOW() WHERE name =\"".$_[0]."\" ";
		my $sth_error = $dbh->prepare($error_sql);
		$sth_error->execute;
		my $status = $mail->send(
		from    => 'xxxx' ,
		to      => '$email' ,
		subject => "VAROVNANI" ,
		msg     => "Vas webhosting $_[0] se blizi k horni hranici weboveho prostoru! Prosim, proverte velikosti dat a DB aby nedoslo k blokaci Vaseho webhostingu" ,
		) ;
		if (!$status) { print $mail->error ;}
	}
	else
	{
		my $error_sql = "UPDATE list SET status = 2 WHERE name = \"".$_[0]."\";";
		my $sth_error = $dbh->prepare($error_sql);
		$sth_error->execute;
	}
	return print "Webhosting $_[0] - Status: ERROR!"; # >1490Mb<1500Mb 
}

sub phase_four(){

		###find email
		my $email = `grep "# LDAP login:" -ri $CONFIG_PATH$_[0].conf`;
		$email=~ s/ //g;
		$email=~ s/#LDAPlogin://gi;
		
		my $fatal_sql = "UPDATE list SET status = 4, blocked = 1, date=NOW() WHERE name =\"".$_[0]."\" ";
		my $sth_fatal = $dbh->prepare($fatal_sql);
		$sth_fatal->execute;
		
		
		my $status = $mail->send(
		from    => 'xxxx' ,
		to      => '$email' ,
		subject => "ZABLOKOVANI VASEHO WEBHOSTINGU" ,
		msg     => "Vas webhosting $_[0] byl nyni zablokovan. Kontaktujte prosim spravce pomoci HelpDesku, k vyreseni problemu." ,
		) ;
		if (!$status) { print $mail->error ;}
	
		#system("chmod 0 $WEB_PATH/$_[0]");
		return print "Webhosting $_[0] - Status: Fatal ERROR! BLOCKED!"; # >1500Mb
}

###################SUBROUTINES#######################


