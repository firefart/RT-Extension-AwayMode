use inc::Module::Install;

RTx 'RT-Extension-AwayMode';
all_from 'lib/RT/Extension/AwayMode.pm';
readme_from 'lib/RT/Extension/AwayMode.pm';
license 'gplv2';

requires_rt('6.0.0');

sign;
WriteAll;
