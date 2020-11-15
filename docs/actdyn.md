# NAME

actdyn - A Mo-99/Tc-99m activity dynamics simulator

# SYNOPSIS

    perl actdyn.pl [-i|-d] [--nofm] [--verbose] [--nopause]

# DESCRIPTION

    actdyn calculates and generates data of the activity dynamics of
    Mo-99/Tc-99m produced via the Mo-100(g,n)Mo-99 reaction.
    Parameters that can be specified via the interactive mode include:
        - Fluence data: directory name, filename rules, and beam energy range
        - Cross section data
        - Mo target materials (options: metallic Mo, MoO2, MoO3)
        - Mo-100 mass fraction
        - The beam energy for which Mo-99/Tc-99m activity dynamics data
          will be calculated
        - Average beam current
        - Time frames: time of irradiation, time of postirradiation processing,
          and time of Tc-99m generator delivery
        - The fractions of Mo-99 and Tc-99m activities
          lost during postirradiation processing
        - Tc-99m elution conditions: elution efficiency, whether to discard
          the first eluate, elution intervals, and Tc-99m generator shelf-life
    The generated data files (.dat) follow the gnuplot data structure
    (data block and dataset).

# OPTIONS

    -i
        Run on the interactive mode.

    -d
        Run on the default mode.

    --nofm
        The front matter will not be displayed at the beginning of the program.

    --verbose (short form: --verb)
        Calculation processes will be displayed.

    --nopause
        The shell will not be paused at the end of the program.
        Use it for a batch run.

# EXAMPLES

    perl actdyn.pl -d --nopause
    perl actdyn.pl --verbose

# REQUIREMENTS

    Perl 5
        Excel::Writer::XLSX
    PHITS
        Please note that since only licensed users are allowed to use PHITS,
        I opted not to upload PHITS-generated photon fluence files
        which are necessary to run actdyn.
        If you already have the license, please obtain T-Track files
        with axis=eng used, and name the tally files in sequential order.
        You can specify the naming rules of the fluence files and their
        directory via the interactive input.

# SEE ALSO

[actdyn on GitHub](https://github.com/jangcom/actdyn)

[actdyn-generated data in a paper: _Phys. Rev. Accel. Beams_ **20** (2017) 104701 (Figs. 4, 5, 12, and 13)](https://doi.org/10.1103/PhysRevAccelBeams.20.104701)

# AUTHOR

Jaewoong Jang <jangj@korea.ac.kr>

# COPYRIGHT

Copyright (c) 2016-2020 Jaewoong Jang

# LICENSE

This software is available under the MIT license;
the license information is found in 'LICENSE'.
