#!/usr/bin/perl
# delete_client.cgi
# Odstráni klienta z wg0.conf po potvrdení

require './wireguard-lib.pl';
&error_setup($text{'delete_err'});
&ReadParse();

my $octet = $in{'octet'};
&error($text{'err_octet'}) if ($octet !~ /^\d+$/);
my ($head, $peers) = &parse_conf();
my $p = &find_peer($peers, $octet);
&error($text{'err_nopeer'}) if (!$p);

if ($in{'confirm'}) {
	my $warn = &delete_client($octet);
	&webmin_log("delete", "client", $p->{'name'});
	&error(&text('save_warn', &html_escape($warn))) if ($warn);
	&redirect("");
	exit;
	}

&ui_print_header(undef, $text{'delete_title'}, "");
print &text('delete_ask', "<b>".&html_escape($p->{'name'})."</b>",
	    "<tt>".&html_escape($p->{'allowed'})."</tt>"),"<p>\n";
print &ui_form_start("delete_client.cgi", "post");
print &ui_hidden("octet", $octet);
print &ui_hidden("confirm", 1);
print &ui_form_end([ [ "go", $text{'delete_ok'} ] ]);
&ui_print_footer("", $text{'index_return'});
