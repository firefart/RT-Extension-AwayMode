use inc::Module::Install;

RTx 'RT-Extension-AwayMode';
all_from 'lib/RT/Extension/AwayMode.pm';
readme_from 'lib/RT/Extension/AwayMode.pm';
license 'gplv2';

requires_rt('6.0.0');
requires_perl('5.36.0');

sign;
WriteAll;
