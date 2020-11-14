@echo off
set rpt_path=./lines_counted
set actdyn_path=..
set file1=%actdyn_path%/actdyn.pl

lcounter.pl --path=%rpt_path% %file1%
