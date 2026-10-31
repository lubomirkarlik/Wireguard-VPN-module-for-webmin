#!/usr/bin/perl
# edit_server.cgi
# Úprava nastavení servera: port, adresy v tuneli, karta, kľúč servera

require './wireguard-lib.pl';
&ReadParse();
&ui_print_header(undef, $text{'edit_title'}, "");

my $s = &get_server_settings();
&error($text{'err_server'}) if (!$s);

print "<b>$text{'edit_warn'}</b><p>\n";
print &ui_form_start("save_server.cgi", "post");
print &ui_table_start($text{'edit_title'}, "width=100%", 2);
print &ui_table_row($text{'edit_port'}, &ui_textbox("port", $s->{'port'}, 6));
print &ui_table_row($text{'setup_v4'}, &ui_textbox("v4", $s->{'v4'}, 20));
print &ui_table_row($text{'setup_v6'},
	&ui_textbox("v6", $s->{'v6'}, 30)."<br><small>$text{'setup_v6_d'}</small>");
print &ui_table_row($text{'setup_nic'}, &ui_textbox("nic", $s->{'nic'}, 15));
print &ui_table_row($text{'index_pub'}, "<tt>".&html_escape($s->{'pubkey'})."</tt>");
print &ui_table_row($text{'edit_regen'},
	&ui_yesno_radio("regen", 0)."<br><small>$text{'edit_regen_d'}</small>");
print &ui_table_end();
print &ui_form_end([ [ "go", $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});
