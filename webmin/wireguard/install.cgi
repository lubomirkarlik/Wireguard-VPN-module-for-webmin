#!/usr/bin/perl
# install.cgi
# Stav inštalácie WireGuardu, inštalácia a odinštalovanie

require './wireguard-lib.pl';
&ReadParse();
&ui_print_header(undef, $text{'inst_title'}, "");

my $st = &get_install_status();
print &install_status_table($st);

# Inštalácia balíkov
print &ui_hr();
print "<h3>$text{'inst_install'}</h3>\n";
my @need = &missing_packages();
if (@need) {
	print &text('inst_missing', "<tt>".join(" ", @need)."</tt>"),"<p>\n";
	print &ui_form_start("install_pkgs.cgi", "post");
	print &ui_form_end([ [ "go", $text{'inst_install_btn'} ] ]);
	}
else {
	print "$text{'inst_all_ok'}<p>\n";
	}

# Odinštalovanie
print &ui_hr();
print "<h3>$text{'inst_uninstall'}</h3>\n";
print $text{'inst_uninstall_d'},"<p>\n";
print &ui_form_start("uninstall.cgi", "post");
print &ui_table_start($text{'inst_uninstall'}, "width=100%", 2);
print &ui_table_row($text{'inst_o_backup'},
	&ui_yesno_radio("backup", 1)."<br><small>".
	&text('inst_o_backup_d', "<tt>".&html_escape($config{'backup_dir'})."</tt>")."</small>");
print &ui_table_row($text{'inst_o_ufw'},
	&ui_yesno_radio("ufw", $st->{'ufw'} eq 'active' ? 1 : 0).
	"<br><small>$text{'inst_o_ufw_d'}</small>");
print &ui_table_row($text{'inst_o_sysctl'},
	&ui_yesno_radio("sysctl", 1)."<br><small>".
	&text('inst_o_sysctl_d', "<tt>".&html_escape($config{'sysctl_file'})."</tt>")."</small>");
print &ui_table_row($text{'inst_o_conf'},
	&ui_yesno_radio("remove_conf", 1)."<br><small>".
	&text('inst_o_conf_d', "<tt>".&html_escape($config{'conf_dir'})."</tt>")."</small>");
print &ui_table_row($text{'inst_o_pkgs'},
	&ui_yesno_radio("remove_packages", 0)."<br><small>$text{'inst_o_pkgs_d'}</small>");
print &ui_table_row(&text('inst_o_confirm', "<tt>".&html_escape($config{'interface'})."</tt>"),
	&ui_textbox("confirm_text", "", 15));
print &ui_table_end();
print &ui_form_end([ [ "go", $text{'inst_uninstall_btn'} ] ]);

&ui_print_footer("", $text{'index_return'});
