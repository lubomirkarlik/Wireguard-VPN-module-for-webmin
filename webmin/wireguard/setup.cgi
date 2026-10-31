#!/usr/bin/perl
# setup.cgi
# Formulár prvotného nastavenia servera (rovnako ako regen-wg.sh)

require './wireguard-lib.pl';
&ReadParse();
&ui_print_header(undef, $text{'setup_title'}, "");

print $text{'setup_desc'},"<p>\n";
if (-r &conf_file()) {
	print "<b>$text{'setup_exists'}</b><p>\n";
	}

my $missing = !&has_command($config{'wg'}) || !&has_command($config{'qrencode'});
print &ui_form_start("setup_server.cgi", "post");
print &ui_table_start($text{'setup_title'}, "width=100%", 2);
print &ui_table_row($text{'setup_endpoint'},
	&ui_textbox("endpoint", &get_endpoint(), 40));
print &ui_table_row($text{'setup_port'}, &ui_textbox("port", 59656, 6));
print &ui_table_row($text{'setup_nic'}, &ui_textbox("nic", &detect_nic(), 15));
print &ui_table_row($text{'setup_v4'}, &ui_textbox("v4", "10.66.66.1/24", 20));
print &ui_table_row($text{'setup_v6'},
	&ui_textbox("v6", "fd42:42:42::1/64", 30)."<br><small>$text{'setup_v6_d'}</small>");
print &ui_table_row($text{'setup_install'},
	&ui_yesno_radio("install", $missing ? 1 : 0)."<br><small>$text{'setup_install_d'}</small>");
print &ui_table_row($text{'setup_firewall'},
	&ui_yesno_radio("firewall", 1)."<br><small>$text{'setup_firewall_d'}</small>");
print &ui_table_end();
print &ui_form_end([ [ "go", $text{'setup_go'} ] ]);

&ui_print_footer("", $text{'index_return'});
