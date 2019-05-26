# actdyn

<?xml version="1.0" ?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="content-type" content="text/html; charset=utf-8" />
<link rev="made" href="mailto:" />
</head>

<body>



<ul id="index">
  <li><a href="#NAME">NAME</a></li>
  <li><a href="#SYNOPSIS">SYNOPSIS</a></li>
  <li><a href="#DESCRIPTION">DESCRIPTION</a></li>
  <li><a href="#OPTIONS">OPTIONS</a></li>
  <li><a href="#EXAMPLES">EXAMPLES</a></li>
  <li><a href="#REQUIREMENTS">REQUIREMENTS</a></li>
  <li><a href="#SEE-ALSO">SEE ALSO</a></li>
  <li><a href="#AUTHOR">AUTHOR</a></li>
  <li><a href="#COPYRIGHT">COPYRIGHT</a></li>
  <li><a href="#LICENSE">LICENSE</a></li>
</ul>

<h1 id="NAME">NAME</h1>

<p>actdyn - A Mo-99/Tc-99m activity dynamics simulator</p>

<h1 id="SYNOPSIS">SYNOPSIS</h1>

<pre><code>    perl actdyn.pl [-d] [-nofm] [-verbose] [-nopause]</code></pre>

<h1 id="DESCRIPTION">DESCRIPTION</h1>

<pre><code>    Running on interactive mode, actdyn calculates and generates data for
    the activity dynamics of Mo-99/Tc-99m produced via the Mo-100(g,n)Mo-99
    reaction.</code></pre>

<h1 id="OPTIONS">OPTIONS</h1>

<pre><code>    -d
        Skip the interactive mode and run on the default mode.

    -nofm
        The front matter will not be displayed at the beginning of the program.

    -verbose (short form: -verb)
        Calculation processes will be displayed.

    -nopause
        The shell will not be paused at the end of the program.
        Use it for a batch run.</code></pre>

<h1 id="EXAMPLES">EXAMPLES</h1>

<pre><code>    perl actdyn.pl -d -nopause
    perl actdyn.pl -verbose</code></pre>

<h1 id="REQUIREMENTS">REQUIREMENTS</h1>

<pre><code>    Perl 5
        Excel::Writer::XLSX
    PHITS
        Please note that since only licensed users are allowed to use PHITS,
        I opted not to upload PHITS-generated photon fluence files
        which are necessary to run actdyn.
        If you already have the license, please obtain T-Track files
        with axis=eng used, and name the tally files in sequential order.
        Corresponding modifications should be made on the directory tree
        via the interactive mode.</code></pre>

<h1 id="SEE-ALSO">SEE ALSO</h1>

<p><a href="https://github.com/jangcom/actdyn">actdyn on GitHub</a></p>

<p><a href="https://link.aps.org/doi/10.1103/PhysRevAccelBeams.20.104701">actdyn-generated data in a paper: <i>Phys. Rev. Accel. Beams</i> <b>20</b>, 104701 (Figs. 4, 5, 12, and 13)</a></p>

<h1 id="AUTHOR">AUTHOR</h1>

<p>Jaewoong Jang &lt;jangj@korea.ac.kr&gt;</p>

<h1 id="COPYRIGHT">COPYRIGHT</h1>

<p>Copyright (c) 2016-2019 Jaewoong Jang</p>

<h1 id="LICENSE">LICENSE</h1>

<p>This software is available under the MIT license; the license information is found in &#39;LICENSE&#39;.</p>


</body>

</html>
