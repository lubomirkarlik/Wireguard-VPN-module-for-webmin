# log_parser.pl
# Čitateľné záznamy akcií modulu vo Webmin Actions Log

do 'wireguard-lib.pl';

sub parse_webmin_log
{
my ($user, $script, $action, $type, $object, $p) = @_;
if ($action eq "service") {
	return &text('log_service', "<tt>".&html_escape($object || $p->{'action'})."</tt>");
	}
elsif ($action eq "endpoint") {
	return &text('log_endpoint', "<tt>".&html_escape($object)."</tt>");
	}
return &text('log_'.$action.'_'.$type, "<tt>".&html_escape($object)."</tt>");
}

1;
