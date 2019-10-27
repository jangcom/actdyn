#!/usr/bin/perl
use strict;
use warnings;
use autodie;
use utf8;
use Class::Struct;
use Carp qw(croak);
use DateTime;
use Excel::Writer::XLSX;
use feature qw(say state);
use File::Basename qw(basename);
use File::Copy;
use POSIX;
use constant PI    => 4 * atan2(1, 1);
use constant ARRAY => ref [];
use constant HASH  => ref {};


our $VERSION = '2.32';
our $LAST    = '2019-10-27';
our $FIRST   = '2016-12-15';


#----------------------------------My::Toolset----------------------------------
sub show_front_matter {
    # """Display the front matter."""

    my $prog_info_href = shift;
    my $sub_name = join('::', (caller(0))[0, 3]);
    croak "The 1st arg of [$sub_name] must be a hash ref!"
        unless ref $prog_info_href eq HASH;

    # Subroutine optional arguments
    my(
        $is_prog,
        $is_auth,
        $is_usage,
        $is_timestamp,
        $is_no_trailing_blkline,
        $is_no_newline,
        $is_copy,
    );
    my $lead_symb = '';
    foreach (@_) {
        $is_prog                = 1  if /prog/i;
        $is_auth                = 1  if /auth/i;
        $is_usage               = 1  if /usage/i;
        $is_timestamp           = 1  if /timestamp/i;
        $is_no_trailing_blkline = 1  if /no_trailing_blkline/i;
        $is_no_newline          = 1  if /no_newline/i;
        $is_copy                = 1  if /copy/i;
        # A single non-alphanumeric character
        $lead_symb              = $_ if /^[^a-zA-Z0-9]$/;
    }
    my $newline = $is_no_newline ? "" : "\n";

    #
    # Fill in the front matter array.
    #
    my @fm;
    my $k = 0;
    my $border_len = $lead_symb ? 69 : 70;
    my %borders = (
        '+' => $lead_symb.('+' x $border_len).$newline,
        '*' => $lead_symb.('*' x $border_len).$newline,
    );

    # Top rule
    if ($is_prog or $is_auth) {
        $fm[$k++] = $borders{'+'};
    }

    # Program info, except the usage
    if ($is_prog) {
        $fm[$k++] = sprintf(
            "%s%s - %s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $prog_info_href->{titl},
            $prog_info_href->{expl},
            $newline,
        );
        $fm[$k++] = sprintf(
            "%s%s v%s (%s)%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $prog_info_href->{titl},
            $prog_info_href->{vers},
            $prog_info_href->{date_last},
            $newline,
        );
        $fm[$k++] = sprintf(
            "%sPerl %s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $^V,
            $newline,
        );
    }

    # Timestamp
    if ($is_timestamp) {
        my %datetimes = construct_timestamps('-');
        $fm[$k++] = sprintf(
            "%sCurrent time: %s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $datetimes{ymdhms},
            $newline,
        );
    }

    # Author info
    if ($is_auth) {
        $fm[$k++] = $lead_symb.$newline if $is_prog;
        $fm[$k++] = sprintf(
            "%s%s%s",
            ($lead_symb ? $lead_symb.' ' : $lead_symb),
            $prog_info_href->{auth}{$_},
            $newline,
        ) for (
            'name',
#            'posi',
#            'affi',
            'mail',
        );
    }

    # Bottom rule
    if ($is_prog or $is_auth) {
        $fm[$k++] = $borders{'+'};
    }

    # Program usage: Leading symbols are not used.
    if ($is_usage) {
        $fm[$k++] = $newline if $is_prog or $is_auth;
        $fm[$k++] = $prog_info_href->{usage};
    }

    # Feed a blank line at the end of the front matter.
    if (not $is_no_trailing_blkline) {
        $fm[$k++] = $newline;
    }

    #
    # Print the front matter.
    #
    if ($is_copy) {
        return @fm;
    }
    else {
        print for @fm;
        return;
    }
}


sub validate_argv {
    # """Validate @ARGV against %cmd_opts."""

    my $argv_aref     = shift;
    my $cmd_opts_href = shift;
    my $sub_name = join('::', (caller(0))[0, 3]);
    croak "The 1st arg of [$sub_name] must be an array ref!"
        unless ref $argv_aref eq ARRAY;
    croak "The 2nd arg of [$sub_name] must be a hash ref!"
        unless ref $cmd_opts_href eq HASH;

    # For yn prompts
    my $the_prog = (caller(0))[1];
    my $yn;
    my $yn_msg = "    | Want to see the usage of $the_prog? [y/n]> ";

    #
    # Terminate the program if the number of required arguments passed
    # is not sufficient.
    #
    my $argv_req_num = shift; # (OPTIONAL) Number of required args
    if (defined $argv_req_num) {
        my $argv_req_num_passed = grep $_ !~ /-/, @$argv_aref;
        if ($argv_req_num_passed < $argv_req_num) {
            printf(
                "\n    | You have input %s nondash args,".
                " but we need %s nondash args.\n",
                $argv_req_num_passed,
                $argv_req_num,
            );
            print $yn_msg;
            while ($yn = <STDIN>) {
                system "perldoc $the_prog" if $yn =~ /\by\b/i;
                exit if $yn =~ /\b[yn]\b/i;
                print $yn_msg;
            }
        }
    }

    #
    # Count the number of correctly passed command-line options.
    #

    # Non-fnames
    my $num_corr_cmd_opts = 0;
    foreach my $arg (@$argv_aref) {
        foreach my $v (values %$cmd_opts_href) {
            if ($arg =~ /$v/i) {
                $num_corr_cmd_opts++;
                next;
            }
        }
    }

    # Fname-likes
    my $num_corr_fnames = 0;
    $num_corr_fnames = grep $_ !~ /^-/, @$argv_aref;
    $num_corr_cmd_opts += $num_corr_fnames;

    # Warn if "no" correct command-line options have been passed.
    if (not $num_corr_cmd_opts) {
        print "\n    | None of the command-line options was correct.\n";
        print $yn_msg;
        while ($yn = <STDIN>) {
            system "perldoc $the_prog" if $yn =~ /\by\b/i;
            exit if $yn =~ /\b[yn]\b/i;
            print $yn_msg;
        }
    }

    return;
}


sub show_elapsed_real_time {
    # """Show the elapsed real time."""

    my @opts = @_ if @_;

    # Parse optional arguments.
    my $is_return_copy = 0;
    my @del; # Garbage can
    foreach (@opts) {
        if (/copy/i) {
            $is_return_copy = 1;
            # Discard the 'copy' string to exclude it from
            # the optional strings that are to be printed.
            push @del, $_;
        }
    }
    my %dels = map { $_ => 1 } @del;
    @opts = grep !$dels{$_}, @opts;

    # Optional strings printing
    print for @opts;

    # Elapsed real time printing
    my $elapsed_real_time = sprintf("Elapsed real time: [%s s]", time - $^T);

    # Return values
    if ($is_return_copy) {
        return $elapsed_real_time;
    }
    else {
        say $elapsed_real_time;
        return;
    }
}
#-------------------------------------------------------------------------------


#
# Struct::Class
# > This module exports a routine called 'struct', which emulates
#   C's struct-like datatype that can be used a Perl class.
# > The parentheses around the routine 'struct' can be omitted,
#   by which the syntax can be simplified like:
#   struct <class_name> => { <attribute> => <sigil_or_class_name> }
# > For "real" Perl OOP, the Moose ecosystem should be considered.
#
struct file_type => {
    dat  => '$',
    chk  => '$',
    tmp  => '$',
    xls  => '$',
    xlsx => '$',

    # PHITS
    inp      => '$',
    out      => '$',
    ang      => '$',
    spectrum => '$',
    track    => '$',
    err      => '$',
};

struct symbol => {
    tilde          => '$',
    backtick       => '$',
    exclamation    => '$',
    at_sign        => '$',
    hash           => '$',
    dollor         => '$',
    percent        => '$',
    caret          => '$',
    ampersand      => '$',
    asterisk       => '$',
    paren_lt       => '$',
    paren_rt       => '$',
    dash           => '$',
    underscore     => '$',
    plus           => '$',
    equals         => '$',
    bracket_lt     => '$',
    bracket_rt     => '$',
    curl_lt        => '$',
    curl_rt        => '$',
    backslash      => '$',
    vert_bar       => '$',
    semicolon      => '$',
    colon          => '$',
    quote          => '$',
    double_quote   => '$',
    comma          => '$',
    angle_quote_lt => '$',
    period         => '$',
    angle_quote_rt => '$',
    slash          => '$',
    question       => '$',
    space          => '$',
    tab            => '$',

    # For on-screen warnings
    warning => '$',

    # For the 'alignment' class
    len => '$', # Not only the 'alignment' class
    bef => '$',
    aft => '$',
};

struct data_struct => {
    block             => '$', # gp data block number (not index)
    dataset           => '$', # gp dataset index
    row               => '$', # gp data row index
    file              => '$',
    info              => '@',
    header            => '@',
    header_sep        => '$',
    header_border_len => '$',
    subheader         => '@',
    content           => '@',
    content_sep_opt   => '%',
    content_sep       => '$',
    content_to_header => '%', # For columnar alignment
};

struct display => {
    dt        => '$',
    timestamp => 'timestamp',
    clear     => '$',
    indent    => '$',
    border    => 'symbol',
};

struct timestamp => {
    where_month_is_named    => '$',
    where_month_is_numbered => '$',
};

struct alignment => {
    symb => 'symbol',
};

struct routine => {
    border     => '$',
    header     => '@',
    rpt_arr    => '@',
    is_verbose => '$',
};

struct default => {
    mark => '$',
};

struct metric_pref => {
    symbol => '$',
    factor => '$',
    list   => '%',
};

struct unit => {
    sel          => '$',
    name         => '$',
    symbol       => '$', # e.g. 'A' for ampere and 'Bq' for becquerel
    symbol_recip => '$', # e.g. 'A^-1'
    symb         => '$', # e.g. 'mA' for milliampere and 'MBq' for megabecquerel
    symb_recip   => '$', # e.g. 'mA^-1'
    power_of_10  => '$', # e.g. '-3' for milli and '6' for mega
    factor       => '$', # e.g. 1e-3 for milli and 1e+6 for mega
    list         => '%',
};

struct time_frame => {
    from   => '$',
    to     => '$',
    slot_1 => '$',
    slot_2 => '$',

    # For Mo-99/Tc-99m demand
    yearly  => '$',
    monthly => '$',
    weekly  => '$',
    daily   => '$',
};

struct math_constant => {
    avogadro => '$',
    coulomb  => '$',
};

struct geometry => {
    shape_opt => '%',
    shape     => '$',
    rad1      => '$',
    rad2      => '$', # For a frustum
    hgt       => '$',
};

struct activity => {
    sat         => '$',
    sat_arr     => '@',
    irr         => '$',
    irr_arr     => '@',
    ratio_irr_to_sat_arr => '@', # Ratio of act->irr to act->sat
    dec         => '$',
    dec_arr     => '@',
    elu         => '$', # Tc-99m elution activity
    elu_arr     => '@',
    elu_tot_arr => '@',
};

struct decay => {
    negatron_line_1    => '$',
    negatron_line_2    => '$',
    positron_line_1    => '$',
    positron_line_2    => '$',
    gamma_line_1       => '$',
    gamma_line_2       => '$',
    branching_fraction => '$',
};

struct nuclide => {
    molar_mass             => '$',
    wgt_molar_mass         => '$',
    wgt_avg_molar_mass     => '$',
    nat_occ_isots          => '%',
    name                   => '$',
    symb                   => '$',
    flag                   => '$', # enrich()
    geom                   => 'geometry', # For targetry geometry descriptions
    vol                    => '$',
    mass                   => '$',
    mass_num               => '$',
    atomic_num             => '$',
    mole_ratio_o_to_mo_opt => '%',
    mole_ratio_o_to_mo     => '$',
    num_moles              => '$',
    mass_dens              => '$', # Dependent on mole_ratio_o_to_mo
    num_dens               => '$',
    amt_frac               => '$',
    mass_frac              => '$',
    mass_frac_sum          => '$',
    is_enri_opt            => '%',
    is_enri                => '$',
    enri                   => '$',
    of_int                 => '@', # <-$mo_tar; for different gp datasets

    # For varying enrichment levels
    enri_min => '$',
    enri_max => '$',
    enri_var => '@',

    # For radioactive ones
    half_life_phy  => '$', # Expressed in hour
    dec_const      => '$',
    act            => 'activity',
    sp_act         => 'activity',
    negatron_dec_1 => 'decay',
    negatron_dec_2 => 'decay',
    positron_dec_1 => 'decay',
    positron_dec_2 => 'decay',
    gamma_dec1     => 'decay',
    gamma_dec2     => 'decay',

    # Tc-99m average dose
    avg_dose => '$',

    # For target materials
    therm_cond => '$',
    melt_point => '$',
    boil_point => '$',

    # Target postprocessing
    processing_time      => '$',
    processing_loss_rate => '$',
};

struct mc_sim => {
    path  => '$',
    bname => '$',
    flag  => 'file_type',
    ext   => 'file_type',
    flues => '@',

    # To be shared with other classes: fname designators
    inp => '$',
    out => '$',
    ang => '$',
};

struct cross_section => {
    inp    => '$',
    micro  => '@',
    idx    => '$',
    is_chk => '$',
};

struct pointwise_multiplication => {
    pointwise     => '@', # Pointwise product
    chk           => '$',
    is_chk        => '$',
    gross         => '$', # Sum of all PWPs at each e-beam energy
    is_show_gross => '$',
};

struct gnuplot => {
    cmt_symb        => '$',
    cmt_border      => 'symbol',
    file_header     => 'data_struct',
    col             => 'data_struct',
    idx             => 'data_struct',
    end_of          => 'data_struct',
    ext             => 'file_type',
    missing_dat_str => '$', # String denoting missing data
    cmd             => '$', # Terminal command to run gnuplot

    dat => '$',
    tmp => '$',
    inp => '$',

    # $mark_time_frame_of
    non => '$',
    eoi => '$',
    eop => '$',
    eod => '$',
    elu => '$',
};

struct comma_separated_values => {
    sep       => '$',
    is_quoted => '$',
    quoted    => '$',
    header    => '@',
    ext       => '$',
};

struct ms_excel => {
    ext => 'file_type',
};

struct linac => {
    name             => '$',
    op_nrg           => '$',
    op_avg_beam_curr => '$',
    num_linacs       => '$',
    list             => '%',

    # For calculation of Tc-99m supply and demand
    tc99m_supply => 'time_frame',
};

struct chemical_processing => {
    predef_opt              => '%',
    is_overwrite            => '$',
    mo99_loss_ratio_at_eop  => '$',
    tc99m_loss_ratio_at_eop => '$',
    time_required           => 'time_frame',
};

struct tc99m_generator => {
    is_overwrite    => '$',
    predef_opt      => '%',
    maker           => '$',
    delivery_time   => 'time_frame',
    elu_eff         => '$',
    elu_ord_count   => '$', # Ordinal count
    elu_ord_from    => '$',
    elu_discard_opt => '%',
    elu_ord_to      => '$',
    elu_itv         => '$',
    tot_num_of_elu  => '$',
    shelf_life      => '$',
};

struct actdyn => {
    path         => '$',
    bname        => '$',
    flag         => 'file_type',
    ext          => 'file_type',
    phits        => 'mc_sim',
    pwm          => 'pointwise_multiplication',
    rrate        => '$',
    gp           => 'gnuplot',
    excel        => 'file_type',
    nrgs_of_int  => '@',
    is_calc_disp => '$',
    tirrs_of_int => '@',
    mo99_act_sat => '$',
    is_run       => '$',
};

struct country => {
    list             => '%',
    name             => '$',
    mo99_demand_num  => 'time_frame',
    mo99_demand_act  => 'time_frame',
    tc99m_demand_num => 'time_frame',
    tc99m_demand_act => 'time_frame',
    req_num_linacs   => '$',
};


#
# Class instantiations using the built-in constructor method
#
my $symb = symbol->new();
my $disp = display->new(
    timestamp => timestamp->new(),
    border    => symbol->new(),
);
my $alignment = alignment->new(
    symb => symbol->new(),
);
my $routine = routine->new();
my $routine_fix_time_frames = routine->new();
my $routine_fix_max_ord = routine->new();
my $dflt = default->new();
my $exa = metric_pref->new();
my $peta = metric_pref->new();
my $tera = metric_pref->new();
my $giga = metric_pref->new();
my $mega = metric_pref->new();
my $kilo = metric_pref->new();
my $hecto = metric_pref->new();
my $deca = metric_pref->new();
my $no_metric_pref = metric_pref->new();
my $deci = metric_pref->new();
my $centi = metric_pref->new();
my $milli = metric_pref->new();
my $micro = metric_pref->new();
my $nano = metric_pref->new();
my $pico = metric_pref->new();
my $femto = metric_pref->new();
my $atto = metric_pref->new();
my $kelv = metric_pref->new();
my $kelv_to_cels = metric_pref->new();
my $bq_per_ci = metric_pref->new();
my $hr_per_sec = metric_pref->new();
my $hr_per_min = metric_pref->new();
my $hr_per_day = metric_pref->new();
my $metric_pref = metric_pref->new();
my $nrg = unit->new();
my $curr = unit->new();
my $power = unit->new();
my $dim = unit->new();
my $len = unit->new();
my $area = unit->new();
my $vol = unit->new();
my $num_dens = unit->new();
my $mass = unit->new();
my $mass_dens = unit->new();
my $mol = unit->new();
my $molar_mass = unit->new();
my $act = unit->new();
my $sp_act = unit->new();
my $temp = unit->new();
my $therm_cond = unit->new();
my $time = unit->new();
my $unit = unit->new();
my $t_tot = time_frame->new();
my $t_irr = time_frame->new();
my $t_pro = time_frame->new();
my $t_del = time_frame->new();
my $t_dec = time_frame->new();
my $t_elu = time_frame->new();
my $const = math_constant->new();
my $geom = geometry->new();
my $w    = nuclide->new();
my $w180 = nuclide->new();
my $w182 = nuclide->new();
my $w183 = nuclide->new();
my $w184 = nuclide->new();
my $w186 = nuclide->new();
my $o    = nuclide->new();
my $o16  = nuclide->new();
my $o17  = nuclide->new();
my $o18  = nuclide->new();
my $mo   = nuclide->new();
my $mo92 = nuclide->new();
my $mo94 = nuclide->new();
my $mo95 = nuclide->new();
my $mo96 = nuclide->new();
my $mo97 = nuclide->new();
my $mo98 = nuclide->new();
my $mo99 = nuclide->new(
    act    => activity->new(),
    sp_act => activity->new(),
    negatron_dec_1 => decay->new(),
    negatron_dec_2 => decay->new(),
);
my $mo100 = nuclide->new();
my $photonucl_tar = nuclide->new(
    geom => geometry->new(),
);
my $converter = nuclide->new(
    geom => geometry->new(),
);
my $mo_tar = nuclide->new(
    geom => geometry->new(),
);
my $mo_met = nuclide->new();
my $mo_diox = nuclide->new();
my $mo_triox = nuclide->new();
my $tc = nuclide->new();
my $tc99 = nuclide->new();
my $tc99m = nuclide->new(
    act         => activity->new(),
    sp_act      => activity->new(),
    gamma_dec1 => decay->new(),
    gamma_dec2 => decay->new(),
);
my $phits = mc_sim->new(
    flag => file_type->new(),
    ext  => file_type->new(),
);
my $xs = cross_section->new();
my $gp = gnuplot->new(
    cmt_border  => symbol->new(),
    file_header => data_struct->new(),
    col         => data_struct->new(),
    idx         => data_struct->new(),
    end_of      => data_struct->new(),
    ext         => file_type->new(),
);
my $mark_time_frame_of = gnuplot->new();
my $excel = ms_excel->new(
    ext => file_type->new(),
);
my $csv = comma_separated_values->new();
my $linac = linac->new(
    tc99m_supply => time_frame->new(),
);
my $chem_proc = chemical_processing->new(
    time_required => time_frame->new(),
);
my $tc99m_gen = tc99m_generator->new(
    delivery_time => time_frame->new(),
);
my $actdyn = actdyn->new(
    flag  => file_type->new(),
    ext   => file_type->new(),
    pwm   => pointwise_multiplication->new(),
    phits => mc_sim->new(),
);
my $mo99_act_nrg_tirr = actdyn->new(
    gp    => gnuplot->new(),
    excel => file_type->new(),
);
my $mo99_act_nrg = actdyn->new(
    gp    => gnuplot->new(),
    excel => file_type->new(),
);
my $mo99_tc99m_actdyn = actdyn->new(
    gp    => gnuplot->new(),
    excel => file_type->new(),
);
my $country = country->new();
my $world = country->new(
    mo99_demand_num  => time_frame->new(),
    mo99_demand_act  => time_frame->new(),
    tc99m_demand_num => time_frame->new(),
    tc99m_demand_act => time_frame->new(),
    req_num_linacs   => linac->new(),
);
my $usa = country->new(
    mo99_demand_num  => time_frame->new(),
    mo99_demand_act  => time_frame->new(),
    tc99m_demand_num => time_frame->new(),
    tc99m_demand_act => time_frame->new(),
    req_num_linacs   => linac->new(),
);
my $eur = country->new(
    mo99_demand_num  => time_frame->new(),
    mo99_demand_act  => time_frame->new(),
    tc99m_demand_num => time_frame->new(),
    tc99m_demand_act => time_frame->new(),
    req_num_linacs   => linac->new(),
);
my $jpn = country->new(
    mo99_demand_num  => time_frame->new(),
    mo99_demand_act  => time_frame->new(),
    tc99m_demand_num => time_frame->new(),
    tc99m_demand_act => time_frame->new(),
    req_num_linacs   => linac->new(),
);


sub parse_argv {
    # """@ARGV parser"""

    my(
        $argv_aref,
        $cmd_opts_href,
        $run_opts_href,
    ) = @_;
    my %cmd_opts = %$cmd_opts_href; # For regexes

    # Parser: Overwrite default run options if requested by the user.
    foreach (@$argv_aref) {
        # Run on the interactive mode.
        if (/$cmd_opts{inter}/) {
            $run_opts_href->{is_inter} = 1;
        }

        # Run on the default mode.
        if (/$cmd_opts{dflt}/) {
            $run_opts_href->{is_dflt} = 1;
        }

        # The front matter won't be displayed at the beginning of the program.
        if (/$cmd_opts{nofm}/) {
            $run_opts_href->{is_nofm} = 1;
        }

        # Reporting levels
        if (/$cmd_opts{verbose}/) {
            $run_opts_href->{is_verbose} = 1;
        }

        # The shell won't be paused at the end of the program.
        if (/$cmd_opts{nopause}/) {
            $run_opts_href->{is_nopause} = 1;
        }
    }
    $routine->is_verbose($run_opts_href->{is_verbose});

    return;
}


sub calc_alignment_symb_len {
    # """Using a string, its reference string, and an alignment option,
    # calculate the number of characters required for the string alignment."""

    # $_[0]: The string to be aligned
    # $_[1]: The length of a string for which the number of alignment characters
    #        for $_[0] will be calculated.
    # $_[2]: Alignment options
    my $len_str_of_int = length shift;
    my $len_ref_str    = shift; # To be a number
    my $align_meth     = shift;

    #
    # [0] Ragged
    #
    # > The ragging direction is not determined here; it should rather be
    #   determined by the position of the symbol-printing command
    #   relative to the string of interest.
    #   e.g. print "This text to be aligned ragged right";
    #        print ($alignment->symb->aft x $alignment->symb->len);
    #   e.g. print ($alignment->symb->bef x $alignment->symb->len);
    #        print "This text to be aligned ragged left";
    #
    if ($align_meth =~ /0|rag/i) {
        # Initialization: depends on $align_meth
        $alignment->symb->len(0);

        for (my $i=1; $i<=($len_ref_str - $len_str_of_int); $i++) {
            # The one at the last iteration will be the return value.
            $alignment->symb->len(
                $alignment->symb->len + 1
            );
        }
    }

    #
    # [1] Centered
    #
    # > As in [0] Ragged ... above, the alignment direction is determined
    #   by the position of the symbol-printing command
    #   relative to the string of interest.
    #   e.g. print ($alignment->symb->bef x $alignment->symb->len);
    #        print "This text to be aligned centered";
    #        print ($alignment->symb->aft x $alignment->symb->len);
    # > Note that the latter symbol-printing command is optional;
    #   a visible difference is made when '$alignment->symb->aft'
    #   differs from '$alignment->symb->bef';
    #   e.g. ---------- This text to be aligned centered **********
    #
    # Below, the '-2' secures two spaces at the front and rear of
    # the string of interest, and the '/2' halves the number of
    # the symbols so that the calculated number can be used
    # evenly at the front and rear.
    #
    elsif ($align_meth =~ /1|center/i) {
        # Initialization: depends on $align_meth
        $alignment->symb->len(1);

        for (
            my $i=1;
            $i<=(($len_ref_str - $len_str_of_int- 2) / 2);
            $i++
        ) {
            # The one at the last iteration is the return
            $alignment->symb->len(
                $alignment->symb->len + 1
            );
        }
    }

    return;
}


sub create_timestamp {
    # """Create a timestamp using the DateTime module."""

    $disp->dt(DateTime->now(time_zone => 'local')); # 'local' required

    # Some methods of the DateTime class
    #
    # ymd(<optional_separator>): 2017-01-02 (dash is the default sep)
    # hms(<optional_separator>): 16:51:10 (colon is the default sep)
    # month_name(): March
    # month_abbr(): Mar
    # day_name():   Friday
    # day_abbr():   Fri
    $disp->timestamp->where_month_is_numbered(
        sprintf(
            "%s (%s.) %s",
            $disp->dt->ymd('/'),
            $disp->dt->day_abbr,
            $disp->dt->hms,
        )
    );

    $disp->timestamp->where_month_is_named(
        sprintf(
            "%s %s, %s (%s.) %s",
            $disp->dt->month_name,
            $disp->dt->day,
            $disp->dt->year,
            $disp->dt->day_abbr,
            $disp->dt->hms,
        )
    );

    return;
}


sub show_routine_header {
    # """Show the name of the subroutine."""

    my $the_caller_routine = shift;
    calc_alignment_symb_len(
        $the_caller_routine,
        length $disp->border->dash,
        'centered',
    );
    $the_caller_routine =
        ($alignment->symb->bef x $alignment->symb->len).
        $the_caller_routine;

    my $k = 0;
    @{$routine->header} = ();
    $routine->header->[$k++] = $disp->border->equals;
    $routine->header->[$k++] = "";
    $routine->header->[$k++] = $the_caller_routine;
    $routine->header->[$k++] = "";
    $routine->header->[$k++] = $disp->border->equals;

    print "\n";
    say for @{$routine->header};

    return;
}


sub pause_terminal {
    # """Pause the terminal until an input is given."""

    my $opt_str = shift;

    printf(
        "%s%s",
        $disp->indent // ' ',
        $opt_str ? $opt_str : 'Press enter to continue...'
    );
    while (<STDIN>) { last }

    return;
}


sub lengthen_cmt_border {
    # """Lengthen the comment border with respect to
    # the total width of its columnar header."""

    # $_[0]: An object to which the data_struct class is nested
    # $_[1]: aref; indices of nonheader
    # $_[2]: aref; indices of borders
    # $_[3]: gnuplot comment symbol
    # $_[4]: Border symbol
    my $obj_having_header = $_[0];
    my @nonheader_indices = @{$_[1]};
    my @border_indices    = @{$_[2]};
    my $cmt_symb          = $_[3];
    my $border_symb       = $_[4];

    # Calculate the new length of the border.
    $obj_having_header->col->header_border_len(0);
    for (my $i=0; $i<=$#{$obj_having_header->col->header}; $i++) {
        next if grep { $i == $_ } @nonheader_indices;

        $obj_having_header->col->header_border_len(
            $obj_having_header->col->header_border_len
            + length($obj_having_header->col->header->[$i])
            + length($obj_having_header->col->header_sep)
        );
    }

    # Lengthen and renew the borders.
    foreach (@border_indices) {
        $obj_having_header->col->header->[$_] = sprintf(
            "%s%s",
            $cmt_symb,
            $border_symb x $obj_having_header->col->header_border_len
        );
    }

    return;
}


sub notify_file_gen {
    say $disp->indent."[$_] generated." for grep { -e } @_;

    return;
}


sub calc_vol_and_mass {
    # """Calculate the volume and mass of a material."""

    my $obj_embracing_geom = shift;

    #
    # Calculate the volume of the material.
    #

    # Shape [0]
    # > Right circular cylinder
    if ($obj_embracing_geom->geom->shape == 0) {
        $obj_embracing_geom->vol(
            PI
            * $obj_embracing_geom->geom->rad1**2
            * $obj_embracing_geom->geom->hgt
        );
    }

    # Shape [1]
    # > Conical frustum
    elsif ($obj_embracing_geom->geom->shape == 1) {
        $obj_embracing_geom->vol(
            (PI/3) * (
                $obj_embracing_geom->geom->rad1**2 + (
                    $obj_embracing_geom->geom->rad1
                    * $obj_embracing_geom->geom->rad2
                ) + $obj_embracing_geom->geom->rad2**2
            ) * $obj_embracing_geom->geom->hgt
        );
    }

    # Unidentified shape
    else { printf("%sShape unidentified.\n", $disp->indent) }

    #
    # Calculate the mass of the material using the volume calculated
    # above and its predefined mass density.
    #
    $obj_embracing_geom->mass(
        $obj_embracing_geom->vol
        * $obj_embracing_geom->mass_dens
    );

    return;
}


sub assign_symb_to_mo_tar {
    # """Assign a symbol to a molybdenum target."""

    $mo_tar->symb(
        $mo_tar->mole_ratio_o_to_mo_opt->{$mo_tar->mole_ratio_o_to_mo}
    );

    return;
}


sub commify {
    # """Commify a number."""

    my ($sign, $int, $dec) = ($_[0] =~ /^([+-]?)([0-9]*)(.*)/);
    my $commified = (
        reverse scalar join ',',
            unpack '(A3)*',
                scalar reverse $int
    );

    return $sign.$commified.$dec;
}


sub gp_to_csv {
    # """Convert a generated gnuplot data file to a CSV file."""

    # $_[0]: Basename of a gnuplot data file
    # $_[1]: Flag to be added to the CSV fname
    # $_[2]: Number of gnuplot datasets (dataset sep: \n\n)
    # $_[3]: New data row interval
    # $_[4]: Index of the gp data x-axis column
    # $_[5]: Indices of the gp data y-axis columns
    my(
        $gp_dat_bname,
        $csv_flag,
        $num_of_datasets,
        $new_data_row_itv,
        $idx_x_axis,
        $idx_y_axes_href,
    ) = @_;
    my @idx_y_axes = @{$idx_y_axes_href};

    # Define the fnames of gp data and CSV.
    my $gp_dat_fname = sprintf(
        "%s.%s",
        $gp_dat_bname,
        $gp->ext->dat,
    );
    my $csv_fname = sprintf(
        "%s%s%s%s.%s",
        $gp_dat_bname,
        '_',
        $csv_flag,
        $csv->ext,
    );

    # Nested arefs for columnar data
    # > Col 1: x-axis
    # > Col 2 onward: y-axis data
    my @csv_col;
    $csv_col[0] = []; # Col 1
    my $num_of_y_axes = $num_of_datasets * ($#idx_y_axes + 1);
    for (my $i=1; $i<=$num_of_y_axes; $i++) {
        $csv_col[$i] = [];
    }

    open my $gp_dat_fh, '<', $gp_dat_fname;
    open my $csv_fh, '>:encoding(UTF-8)', $csv_fname;
    select($csv_fh);

    # Index controls
    my $x_axis_ctrl = 0;
    my $col_count   = 0;
    my $idx_dataset = 0;
    my $idx_row     = 0; # Nested array index
    my $idx_for_next_dataset = 1;
    my @gp_header; # gp data columnar header
    my @gp_row;    # gp data row

    # Read in the gnuplot data file.
    foreach (<$gp_dat_fh>) {
        # Columnar header
        # > Split and modify the columnar header, and write to the CSV file.
        # > Placed here to write only to the first row of the CSV file
        my $gp_cmt_symb = $gp->cmt_symb;

        # The pair of columnar header and data separators:
        # $gp->col->header_sep and $gp->col->content_sep
        # ( | )                and ( ) <- Multiple
        # (\t)                 and (\t)
        # (,)                  and (,)
        @gp_header = split /\|/ if /(?:[a-z]|\))+ [\s]*\|[\s]* [a-z]+/ix;
        @gp_header = split /\t/ if /(?:[a-z]|\))+      \t      [a-z]+/ix;
        @gp_header = split /,/  if /(?:[a-z]|\))+      ,       [a-z]+/ix;

        # Modify and write the columnar header.
        if (/(?:[a-z]|\))+ (?:[\s]*\|[\s]* | \t | ,) [a-z]+/ix) {
            # Remove the comment symbol, and
            # suppress the leading and trailing spaces.
            foreach (@gp_header) {
                s/#//;
                s/^[\s]+//; # When $gp->col->content_sep == '|'
                s/[\s]+$//; # When $gp->col->content_sep == '|'
            }

            # x-axis header
            if ($x_axis_ctrl == 0) { # $x_axis_ctrl: To write only once
                printf(
                    "%s%s%s%s",
                    $csv->quoted, # Can be suppressed via $csv->is_quoted
                    $gp_header[$idx_x_axis],
                    $csv->quoted,
                    $csv->sep,
                );
            }
            $x_axis_ctrl++;

            # y-axis header
            foreach my $idx_y_axis (@idx_y_axes) {
                $col_count++; # Not to insert a comma following the last header
                printf(
                    "%s%s%s",
                    $csv->quoted,
                    $gp_header[$idx_y_axis],
                    $csv->quoted,
                );

                # Insert a comma following a header (except the last).
                print $csv->sep if $col_count != $num_of_y_axes;
            }

            # Line break following the last column header
            print "\n" if $col_count == $num_of_y_axes;
        }

        # Skip a comment line.
        next if /^#/;

        # regex: A blank line; two such blank lines function as
        # a separator of gnuplot datasets
        if (/^$/) {
            $idx_dataset++; # Increment a dataset index
            $idx_row = 0;   # Initialize the first index of a nested array
            next;           # Not to perform $idx_row++ in the last row
        }

        # Split and store the columnar data into @gp_row.
        my $gp_col_content_sep = $gp->col->content_sep;
        @gp_row = split /$gp_col_content_sep+/;

        # x-axis data
        if ($idx_dataset == 0) {
            $csv_col[0][$idx_row] = $gp_row[$idx_x_axis];
        }

        # y-axis data 1, 2, 3
        if ($idx_dataset == 0) {
            my $j = (($#idx_y_axes + 1) * 0) + 1; # ((2 + 1) * 0) + 1 = 1
            for (my $i=0; $i<=$#idx_y_axes; $i++) {
                $csv_col[$j][$idx_row] = $gp_row[$idx_y_axes[$i]];
                $j++; # So that $j = 1->2->3(->4; but 4 is unused)
            }
        }

        # y-axis data 4, 5, 6
        # Perform only if the number of dataset is >= 2.
        # > $idx_dataset is 2 because of the "\n\n".
        if ($num_of_datasets >= 2 and $idx_dataset == 2) {
            my $j = (($#idx_y_axes + 1) * 1) + 1; # ( (2 + 1) * 1 ) + 1 = 4
            for (my $i=0; $i<=$#idx_y_axes; $i++) {
                $csv_col[$j][$idx_row] = $gp_row[$idx_y_axes[$i]];
                $j++; # So that $j = 4->5->6(->7; but 4 is unused)
            }
        }

        # y-axis data 7, 8, 9
        # > Perform only if the number of dataset is >= 3.
        # > iPlots allows up to 10 columns, and the total
        #   number of axes is now 10, including the x-axis.
        # > $idx_dataset is 4 because of the "\n\n"
        if ($num_of_datasets >= 3 and $idx_dataset == 4) {
            my $j = (($#idx_y_axes + 1) * 2) + 1; # ( (2 + 1) * 2 ) + 1 = 7
            for (my $i=0; $i<=$#idx_y_axes; $i++) {
                $csv_col[$j][$idx_row] = $gp_row[$idx_y_axes[$i]];
                $j++; # So that $j = 7->8->9(->10; but 10 is unused)
            }
        }

        # Increment the gnuplot data row index.
        $idx_row++;
    }
    close $gp_dat_fh;

    #
    # Write the data columns to the CSV file.
    #

    # -1: because $idx_row++ increases one more idx
    for (my $j=0; $j<=($idx_row - 1); $j++) {
        # Write the first and last data rows, and
        # data rows whose indices are multiples of $new_data_row_itv.
        if (
            $j == 0
            or $j % $new_data_row_itv == 0 # Modulus
            or $j == ($idx_row - 1)
        ) {
            for (my $i=0; $i<=$num_of_y_axes; $i++) {
                # # Limit of iPlots: Up to 3 decimal places
                printf "%.3e", $csv_col[$i][$j];

                # Insert a comma separator except the last item.
                printf $csv->sep unless $i == $num_of_y_axes;
            }

            # Insert a newline character following the end of
            # a row of the CSV data except the last one.
            print "\n" unless $j == $idx_row - 1;
        }
    }
    select(STDOUT);
    close $csv_fh;

    # Notify CSV generation.
    printf(
        "%sVia %s,",
        $disp->indent,
        (caller(0))[3],
    );
    notify_file_gen($csv_fname);

    return;
}


sub define_fnames_for_actdyn_obj {
    # """Define fnames for actdyn objects."""

    my %objs = (
        mo99_act_nrg_tirr => {
            obj   => $mo99_act_nrg_tirr,
            bname => sprintf(
                "%s_%s",
                $actdyn->bname,
                'mo99_act_nrg_tirr',
            ),
        },
        mo99_act_nrg => {
            obj   => $mo99_act_nrg,
            bname => sprintf(
                "%s_%s",
                $actdyn->bname,
                'mo99_act_nrg',
            ),
        },
        mo99_tc99m_actdyn => {
            obj   => $mo99_tc99m_actdyn,
            bname => sprintf(
                "%s_%s",
                $actdyn->bname,
                'mo99_tc99m_actdyn',
            ),
        },
    );

    foreach my $k (keys %objs) {
        # Redirection
        my $obj   = $objs{$k}{obj};

        # bname
        $obj->bname($objs{$k}{bname});

        # gnuplot files
        $obj->gp->dat(
            $actdyn->path.
            $obj->bname.
            '.'.
            $gp->ext->dat
        );
        $obj->gp->tmp(
            $actdyn->path.
            $obj->bname.
            '.'.
            $gp->ext->tmp
        );
        $obj->gp->inp(
            $actdyn->path.
            $obj->bname.
            '.'.
            $gp->ext->inp
        );

        # Excel files
        $obj->excel->xls(
            $actdyn->path.
            $obj->bname.
            '.'.
            $excel->ext->xls
        );
        $obj->excel->xlsx(
            $actdyn->path.
            $obj->bname.
            '.'.
            $excel->ext->xlsx
        );
    }

    return;
}


sub overwrite_param_via_opt {
    # """Parameter overwriting via predefined options."""

    # $_[0]: The parameter to be overwritten
    # $_[1]: href explaining available options for $_[0]
    my(
        $curr_val,
        $expl_href,
        $expl_str,
    ) = @_;
    my @sorted_keys = sort keys %$expl_href;

    # Show the available options.
    print $disp->indent."[";
    print $expl_str if $expl_str; # Optional
    foreach my $k (@sorted_keys) {
        # Print the key-val pair.
        printf(
            "%s:%s",
            $k,
            (
                $expl_href->{$k} =~ /^[\r\n\f\v ]$/ ? 'Space' :
                $expl_href->{$k} =~ /^\t$/          ? 'Tab'   :
                $expl_href->{$k} =~ /^,$/           ? 'Comma' : $expl_href->{$k}
            ),
        );

        # Mark the current value.
        printf(" (%s)", $dflt->mark) if (
            $k eq $curr_val
            or $expl_href->{$k} eq $curr_val
        );

        # Insert a separator next to an item except the last one.
        print ", " unless $k eq $sorted_keys[-1];
    }
    print "] ";

    # Overwrite the parameter in question.
    chomp(my $new_val = <STDIN>);

    # If the input falls within the available options, return that input,
    # which will then overwrite the parameter in question.
    # Otherwise, return the existing value.
    my $is_within = grep { /$new_val/ } @sorted_keys;
    my $the_return = $is_within ? $new_val : $curr_val;

    printf(
        "%sNow: %s\n",
        $disp->indent,
        $the_return,
    ) if $curr_val ne $the_return;

    return $the_return;
}


sub overwrite_param_via_val {
    # """Parameter overwriting via values."""

    # $_[0]: The parameter to be overwritten
    # $_[1]: A string explaining what $_[0] means
    # $_[2]: Minimum allowed value of $_[0]
    # $_[3]: Maximum allowed value of $_[0]
    my(
        $curr_val,
        $curr_val_expl,
        $min_allowed_val,
        $max_allowed_val,
    ) = @_;
    my $is_arr = ref $curr_val eq ARRAY ? 1 : 0;
    my $is_min = $min_allowed_val ? 1 : 0;
    my $is_max = $max_allowed_val ? 1 : 0;

    if ($is_arr) {
        printf(
            "%s[%s (%s: %s..%s)] ",
            $disp->indent,
            $curr_val_expl,
            $dflt->mark,
            $curr_val->[0],
            $curr_val->[-1],
        );
    }

    else {
        if ($is_min or $is_max) {
            # The decimal separator involved
            if ($curr_val =~ /[.,]/x) {
                printf(
                    "%s[%s: %.5f--%.5f (%s: %.5f)] ",
                    $disp->indent,
                    $curr_val_expl,
                    $min_allowed_val,
                    $max_allowed_val,
                    $dflt->mark,
                    $curr_val,
                );
            }

            # No decimal separator
            else {
                printf(
                    "%s[%s: %g--%g (%s: %g)] ",
                    $disp->indent,
                    $curr_val_expl,
                    $min_allowed_val,
                    $max_allowed_val,
                    $dflt->mark,
                    $curr_val,
                );
            }
        }

        else {
            printf(
                "%s[%s (%s: %s)] ",
                $disp->indent,
                $curr_val_expl,
                $dflt->mark,
                $curr_val,
            );
        }
    }

    # Overwrite the parameter in question.
    chomp(my $new_val = <STDIN>);
    return $curr_val if $new_val =~ /^$/;
    my $the_return;

    if ($is_arr) {
        $the_return = [eval($new_val)];
    }
    else {
        $new_val =~ s/[^\d.,]//g if ($is_min or $is_max);
        # If the input falls within the allowed range, return that value,
        # which will overwrite the parameter in question.
        # Numeral
        $the_return = ($is_min and $new_val >= $min_allowed_val) ?
            $new_val : $curr_val;
        $the_return = ($is_max and $new_val <= $max_allowed_val) ?
            $new_val : $curr_val;
        # String
        $the_return = $new_val if (not $is_min and not $is_max);
    }

    printf(
        "%s[%s] is now: %s\n",
        $disp->indent,
        $curr_val_expl,
        $is_arr ? "@$the_return" : $the_return,
    ) if $curr_val ne $the_return;

    return $the_return;
}


sub overwrite_param {
    # """Prompt the interactive mode for parameter overwriting"""

    # Notification - beginning
    show_routine_header((caller(0))[3]) if $routine->is_verbose;

    # Prompt the user to (y/n)
    my $yn_msg = $disp->indent."Overwrite simulation parameters? [y/n]> ";
    print $yn_msg;
    while (chomp(my $yn = <STDIN>)) {
        if ($yn =~ /\by\b/i) {
            # Fluence data
            $phits->path(
                overwrite_param_via_val(
                    $phits->path,
                    "MC fluence data path",
                )
            );
            $phits->bname(
                overwrite_param_via_val(
                    $phits->bname,
                    "MC fluence data basename (followed by energy)",
                )
            );
            $phits->flag->spectrum(
                overwrite_param_via_val(
                    $phits->flag->spectrum,
                    "MC fluence data flag (following energy)",
                )
            );
            $actdyn->nrgs_of_int(
                overwrite_param_via_val(
                    $actdyn->nrgs_of_int,
                    sprintf(
                        "MC fluence beam energy range in %s",
                        $nrg->symb,
                    ),
                )
            );

            # xs data
            $xs->inp(
                overwrite_param_via_val(
                    $xs->inp,
                    "Microscopic cross section file",
                )
            );

            # Output
            $actdyn->path(
                overwrite_param_via_val(
                    $actdyn->path,
                    "Output path",
                )
            );
            $gp->col->content_sep(
                overwrite_param_via_opt(
                    $gp->col->content_sep,        # Hash key
                    $gp->col->content_sep_opt,    # Hash ref
                    '<Columnar data separator> ', # Optional str for expl
                )
            );

            # Mo target, material
            $mo_tar->mole_ratio_o_to_mo(
                overwrite_param_via_opt(
                    $mo_tar->mole_ratio_o_to_mo,
                    $mo_tar->mole_ratio_o_to_mo_opt,
                )
            );
            assign_symb_to_mo_tar();

            # Mo target, Mo-100 enrichment level
            $mo_tar->is_enri(
                overwrite_param_via_opt(
                    $mo_tar->is_enri,
                    $mo_tar->is_enri_opt,
                )
            );
            if ($mo_tar->is_enri) {
                $mo100->enri(
                    overwrite_param_via_val(
                        $mo100->enri,
                        "Mo-100 mass fraction",
                        0.10146,
                        1.00000,
                    )
                );
            }

            # Beam energy of interest for activity dynamics
            $linac->op_nrg(
                overwrite_param_via_val(
                    $linac->op_nrg,
                    sprintf(
                        "Beam energy of interest for activity dynamics (%s)",
                        $nrg->symb,
                    ),
                    $actdyn->nrgs_of_int->[0],
                    $actdyn->nrgs_of_int->[-1],
                )
            );

            # Beam current of interest
            $linac->op_avg_beam_curr(
                overwrite_param_via_val(
                    $linac->op_avg_beam_curr,
                    sprintf(
                        "Average beam current (%s)",
                        $curr->symb,
                    ),
                    1e-1,
                    1e+3,
                )
            );

            # End of irradiation
            $t_irr->to(
                overwrite_param_via_val(
                    $t_irr->to,
                    "End of irradiation (h)",
                    $t_tot->from,
                    $t_tot->to,
                )
            );

            # Mo target processing settings
            $chem_proc->is_overwrite(
                overwrite_param_via_opt(
                    $chem_proc->is_overwrite,
                    $chem_proc->predef_opt,
                )
            );
            if ($chem_proc->is_overwrite) {
                $chem_proc->time_required->to(
                    overwrite_param_via_val(
                        $chem_proc->time_required->to,
                        "Time required to process irradiated Mo targets (h)",
                        1, # Must be >=1 for correct calc of Tc-99m dec act
                        48,
                    )
                );
                $chem_proc->mo99_loss_ratio_at_eop(
                    overwrite_param_via_val(
                        $chem_proc->mo99_loss_ratio_at_eop,
                        "The fraction of Mo-99 activity".
                        " lost during postirradiation processing",
                        0.0,
                        1.0,
                    )
                );
                $chem_proc->tc99m_loss_ratio_at_eop(
                    overwrite_param_via_val(
                        $chem_proc->tc99m_loss_ratio_at_eop,
                        "The fraction of Tc-99m activity".
                        " lost during postirradiation processing",
                        0.0,
                        1.0,
                    )
                );
            }

            # Tc-99m generator settings
            $tc99m_gen->is_overwrite(
                overwrite_param_via_opt(
                    $tc99m_gen->is_overwrite,
                    $tc99m_gen->predef_opt,
                )
            );
            if ($tc99m_gen->is_overwrite) {
                $tc99m_gen->delivery_time->to(
                    overwrite_param_via_val(
                        $tc99m_gen->delivery_time->to,
                        "Tc-99m generator delivery time (h)",
                        3,   # Must be >=1 for correct calc of Tc-99m dec act
                        168, # 7 days
                    )
                );
                $tc99m_gen->elu_eff(
                    overwrite_param_via_val(
                        $tc99m_gen->elu_eff,
                        "Tc-99m elution efficiency",
                        0.0,
                        1.0,
                    )
                );
                $tc99m_gen->elu_ord_from(
                    overwrite_param_via_opt(
                        $tc99m_gen->elu_ord_from,
                        $tc99m_gen->elu_discard_opt,
                    )
                );
                $tc99m_gen->elu_itv(
                    overwrite_param_via_val(
                        $tc99m_gen->elu_itv,
                        "Intervals between Tc-99m elutions (h)",
                        1, # Must be nonzero as is used for modulus calculation
                        48,
                    )
                );
                $tc99m_gen->shelf_life(
                    overwrite_param_via_val(
                        $tc99m_gen->shelf_life,
                        "Tc-99m generator shelf-life (h)",
                        24,
                        288, # 12 days
                    )
                );
            }

            print $disp->indent."Overwriting completed.\n"
                if $routine->is_verbose;
        }
        last if $yn =~ /\b[yn]\b/i;
        print $yn_msg;
    }
    say $disp->border->dash;

    # Notification - ending
    pause_terminal() if $routine->is_verbose;

    return;
}


sub correct_trailing_path_sep {
    # """Correct the trailing path separator."""

    my @objs = @_;

    foreach (@objs) {
        my $path = $_->path;
        $path =~ s/$/\// if not $path =~ /[\\\/]$/; # No sep
        $path =~ s/[\\\/]{2,}$/\// if $path =~ /[\\\/]{2,}$/; # Multiple seps
        $_->path($path);
    }

    return;
}


sub fix_time_frames {
    # """Fix the time frames dependent on the end of irradiation,
    # which could be overwritten in overwrite_param()."""

    # Notification - beginning
    show_routine_header((caller(0))[3]) if $routine->is_verbose;

    # > $t_irr->to, which contains the end of irradiation (EOI),
    #   could be overwritten in overwrite_param().
    #   As the subsequent time frames have all been set based on the EOI,
    #   they all need to be redefined following overwriting of the EOI.
    # > Time frames are defined in the order of:
    #   $t_irr (targetry irradiation)
    #   $t_dec (decay time)
    #       $t_pro (targetry processing and Tc-99m generator manufacture)
    #       $t_del (Tc-99m generator delivery)

    # Decay time
    # > $t_dec->from is defined and initialized at each $nrg in
    #   "Activity calculation term (3/3): Those functions of time"
    $t_dec->to($t_tot->to - $t_irr->to);

    # Chemical processing time
    $t_pro->from($t_irr->to);
    $t_pro->to($t_pro->from + $chem_proc->time_required->to);

    # Tc-99m generator delivery time
    $t_del->from($t_pro->to);
    $t_del->to($t_del->from + $tc99m_gen->delivery_time->to);

    if ($routine->is_verbose) {
        my $k = 0;
        @{$routine->rpt_arr} = ();
        $routine->rpt_arr->[$k++] = $disp->border->dash;
        $routine->rpt_arr->[$k++] = sprintf(
            "Time frames dependent on \$t_irr->to (%g %s) have been fixed as:",
            $t_irr->to,
            $time->symb,
        );
        $routine->rpt_arr->[$k++] = $routine->rpt_arr->[0];
        $routine->rpt_arr->[$k++] = sprintf(
            "\$t_dec->to   (%g %s) =  ".
            "\$t_tot->to (%g %s) - \$t_irr->to (%g %s)",
            $t_dec->to, $time->symb,
            $t_tot->to, $time->symb,
            $t_irr->to, $time->symb,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "\$t_pro->from (%g %s) =  \$t_irr->to (%g %s)",
            $t_pro->from, $time->symb,
            $t_irr->to, $time->symb,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "\$t_pro->to   (%g %s) =  \$t_pro->from (%g %s)".
            " + \$chem_proc->time_required->to(%g %s)",
            $t_pro->to, $time->symb,
            $t_pro->from, $time->symb,
            $chem_proc->time_required->to, $time->symb,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "\$t_del->from (%g %s) =  \$t_pro->to (%g %s)",
            $t_del->from, $time->symb,
            $t_pro->to, $time->symb,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "\$t_del->to   (%g %s) =  \$t_del->from (%g %s)".
            " + \$tc99m_gen->delivery_time->to(%g %s)",
            $t_del->to, $time->symb,
            $t_del->from, $time->symb,
            $tc99m_gen->delivery_time->to, $time->symb,
        );
        $routine->rpt_arr->[$k] = $routine->rpt_arr->[0];

        for (my $i=0; $i<=$k; $i++) {
            printf(
                "%s%s\n",
                $i !~ /\b[02]|$k\b/ ? $disp->indent : '',
                $routine->rpt_arr->[$i],
            );
        }
    }

    # Notification - ending
    pause_terminal() if $routine->is_verbose;

    return;
}


sub fix_max_ord_of_tc99m_elution {
    # """Fix the maximum ordinal number of Tc-99m elution,
    # which could be overwritten in overwrite_param()."""

    # Notification - beginning
    show_routine_header((caller(0))[3]) if $routine->is_verbose;

    # Fix the maximum ordinal number of Tc-99m elution.
    $tc99m_gen->elu_ord_to(
        # e.g. 240 / 24 = 10 + 1 = 11
        floor( $tc99m_gen->shelf_life / $tc99m_gen->elu_itv )
        + 1
    );

    # Total number of elutions
    # (the real elution count is given in $tc99m_gen->elu_ord_count)
    # The +1 counts (compensates) the first elution ordinal
    $tc99m_gen->tot_num_of_elu(
        $tc99m_gen->elu_ord_to
        - $tc99m_gen->elu_ord_from
        + 1
    );

    # Examine if the sum of the time of end of delivery and the shelf-life of
    # the Tc-99m generator designated exceeds the total time frame.
    my $diff = 0;
    my $excess_num_of_elu = 0;
    if (($t_del->to + $tc99m_gen->shelf_life) > $t_tot->to) {
        # The number of hours in excess
        $diff = ($t_del->to + $tc99m_gen->shelf_life) - $t_tot->to;

        # The number of Tc-99m elutions that will "not" be performed
        # as is beyond the end of the total time frame
        $excess_num_of_elu = ceil($diff / $tc99m_gen->elu_itv);

        # The "correct" total number of Tc-99m elutions
        $tc99m_gen->tot_num_of_elu(
            $tc99m_gen->tot_num_of_elu
            - $excess_num_of_elu
        );
    }

    # A conditional string of the number of elutions
    # in excess; a plural or a singular form of "time"
    my $excess_num_of_elu_str = sprintf(
        "%s time%s",
        $excess_num_of_elu,
        $excess_num_of_elu > 2 ? 's' : '',
    );

    if ($routine->is_verbose) {
        my $k = 0;
        @{$routine->rpt_arr} = ();
        $routine->rpt_arr->[$k++] = $disp->border->dash;
        $routine->rpt_arr->[$k++] = sprintf(
            "The maximum ordinal number of %s elution dependent on",
            $tc99m->symb,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "\$tc99m_gen->elu_itv(%d %s) has been fixed as:",
            $tc99m_gen->elu_itv / $time->factor,
            $time->symb,
        );
        $routine->rpt_arr->[$k++] = $routine->rpt_arr->[0];
        $routine->rpt_arr->[$k++] = sprintf(
            "\$tc99m_gen->elu_ord_to(%d) = ",
            $tc99m_gen->elu_ord_to,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "    floor(\$tc99m_gen->shelf_life(%d %s)".
            " / \$tc99m_gen->elu_itv(%d %s)) + 1",
            $tc99m_gen->shelf_life / $time->factor,
            $time->symb,
            $tc99m_gen->elu_itv / $time->factor,
            $time->symb
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "The elution time frame in excess of".
            " the total time frame is [%g %s].",
            $diff / $time->factor,
            $time->symb,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "    = (%d %s + %d %s)- %d %s",
            $t_del->to / $time->factor,
            $time->symb,
            $tc99m_gen->shelf_life / $time->factor,
            $time->symb,
            $t_tot->to / $time->factor,
            $time->symb
        ) if $diff;
        $routine->rpt_arr->[$k++] = sprintf(
            "Therefore, ceil(%d %s/ %d %s) = %s".
            " of elutions will not be performed.",
            $diff / $time->factor,
            $time->symb,
            $tc99m_gen->elu_itv / $time->factor,
            $time->symb,
            $excess_num_of_elu_str,
        );
        $routine->rpt_arr->[$k] = sprintf(
            "With \$tc99m_gen->elu_ord_from(%d), <- the first %s eluate",
            $tc99m_gen->elu_ord_from,
            $tc99m->symb,
        );
        $routine->rpt_arr->[$k++] .=
            $tc99m_gen->elu_ord_from == 1 ? ' "in"cluded' : ' "ex"cluded';
        $routine->rpt_arr->[$k++] = sprintf(
            "the total number of %s elutions".
            " will be count(%d..%d) - %d = [%d].",
            $tc99m->symb,
            $tc99m_gen->elu_ord_from,
            $tc99m_gen->elu_ord_to,
            $excess_num_of_elu,
            $tc99m_gen->tot_num_of_elu,
        );
        $routine->rpt_arr->[$k] = $routine->rpt_arr->[0];

        for (my $i=0; $i<=$k; $i++) {
            printf(
                "%s%s\n",
                $i !~ /\b[03]|$k\b/ ? $disp->indent : '',
                $routine->rpt_arr->[$i],
            );
        }
    }

    # Notification - ending
    pause_terminal() if $routine->is_verbose;

    return;
}


sub calc_elem_wgt_molar_mass_and_isot_mass_fracs {
    # """Calculate the weighted-average molar mass of an element
    # and the mass fractions of its naturally occurring isotopes"""

    my(
        $elem_href,
        $wgt_frac,
        $is_quiet, # Hook for populate_attrs() caller
    ) = @_;

    # Notification - beginning
    show_routine_header((caller(0))[3])
        if ($routine->is_verbose and not $is_quiet);

    #
    # (1) Calculate the weighted-average molar mass of the element.
    # > Weight the molar masses of the isotopes by $wgt_frac
    # > Sum up the weighted molar masses of the isotopes.
    #

    # Initialize cumul sums.
    $elem_href->wgt_avg_molar_mass(0);
    $elem_href->mass_frac_sum(0);

    # (i) Weight by amount fraction: Weighted "arithmetic" mean
    if ($wgt_frac =~ /am(?:oun)?t/i) {
        foreach my $key (keys %{$elem_href->nat_occ_isots}) {
            # Redirection
            my $isot = $elem_href->nat_occ_isots->{$key};

            # (a) Weight by "multiplication"
            $isot->wgt_molar_mass($isot->$wgt_frac * $isot->molar_mass);

            # (b) (cumul sum) Sum up the weighted molar masses of the.
            $elem_href->wgt_avg_molar_mass(
                $elem_href->wgt_avg_molar_mass + $isot->wgt_molar_mass
            );
        }
    }

    # (ii) Weight by mass fraction: Weighted "harmonic" mean
    elsif ($wgt_frac =~ /mass/i) {
        foreach my $key (keys %{$elem_href->nat_occ_isots}) {
            # Redirection
            my $isot = $elem_href->nat_occ_isots->{$key};
            my $isot_wgt_frac = $isot->$wgt_frac // 0;

            # (1) Weight by "division"
            $isot->wgt_molar_mass($isot_wgt_frac / $isot->molar_mass);

            # (2) (cumul sum) Sum up the weighted molar masses of the.
            #     => Will be the denominator in (4).
            $elem_href->wgt_avg_molar_mass(
                $elem_href->wgt_avg_molar_mass + $isot->wgt_molar_mass
            );

            # (3) Cumulative sum of the mass fractions of the isotopes
            #     => Will be the numerator in (4).
            #     => The final value of the cumulative sum
            #        should be 1 in principle.
            $elem_href->mass_frac_sum(
                $elem_href->mass_frac_sum + $isot_wgt_frac
            );
        }
        # (4) Evaluate the fraction.
        $elem_href->wgt_avg_molar_mass(
            $elem_href->mass_frac_sum # Should be 1 in principle.
            / $elem_href->wgt_avg_molar_mass
        );
    }

    #
    # (2) Calculate mass fractions of the isotopes: (1) divided by (2)
    # > Run only if the amount fraction is the weighting fraction; otherwise,
    #   redistributed mass fractions of the isotopes will be unnecessarily
    #   recalculated, which will then result in wrong calculation.
    #
    if ($wgt_frac =~ /am(?:oun)?t/i) {
        foreach my $key (keys %{$elem_href->nat_occ_isots}) {
            $elem_href->nat_occ_isots->{$key}->mass_frac(
                $elem_href->nat_occ_isots->{$key}->wgt_molar_mass
                / $elem_href->wgt_avg_molar_mass
            );
        }
    }

    if ($routine->is_verbose and not $is_quiet) {
        my $k = 0;
        @{$routine->rpt_arr} = ();
        $routine->rpt_arr->[$k++] = $disp->border->dash;
        $routine->rpt_arr->[$k++] = sprintf(
            "The molar masses of [%s] isotopes".
            " have been weighted to their [%s].",
            $elem_href->name,
            $wgt_frac,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "The sum of the weighted molar masses,".
            " or the weighted-average\n".
            " molar mass of [%s] is now: [%g %s].",
            $elem_href->name,
            $elem_href->wgt_avg_molar_mass,
            $molar_mass->symbol
        );
        if ($wgt_frac =~ /am(?:oun)?t/i) {
            $routine->rpt_arr->[$k++] =
                "Subsequently, the mass fractions of the isotopes".
                " have been calculated.";
        }
        $routine->rpt_arr->[$k] = $routine->rpt_arr->[0];

        for (my $i=0; $i<=$k; $i++) {
            printf(
                "%s%s\n",
                $i !~ /\b[0]|$k\b/ ? $disp->indent : '',
                $routine->rpt_arr->[$i],
            );
            print "\n" if $i =~ /\b[45]\b/;
        }
    }

    # Notification - ending
    pause_terminal()
        if ($routine->is_verbose and not $is_quiet);

    # Check the calculation results.
    show_amt_and_mass_fracs_and_molar_mass($elem_href)
        if ($routine->is_verbose and not $is_quiet);

    return;
}


sub show_amt_and_mass_fracs_and_molar_mass {
    # """Show amount and mass fractions of isotopes of
    # a chemical element and its average molar mass.

    my $elem_href = shift;

    # Notification - beginning
    show_routine_header((caller(0))[3]) if $routine->is_verbose;

    my @lengthiest = sort { length $b <=> length $a }
        keys %{$elem_href->nat_occ_isots};
    my $conv = '%'.(length $lengthiest[0]).'s';

    my $the_first_half;
    my $the_latter_half;
    say $disp->border->dash;
    foreach my $key (sort keys %{$elem_href->nat_occ_isots}) {
        $the_first_half = sprintf(
            "%s[$conv]: amount frac [%.5f];".
            " molar mass [%.3f %s];".
            " weighted molar mass",
            $disp->indent,
            $key,
            $elem_href->nat_occ_isots->{$key}->amt_frac,
            $elem_href->nat_occ_isots->{$key}->molar_mass,
            $molar_mass->symbol,
        );

        $the_latter_half = sprintf(
            " [%6.3f %s]; mass frac [%.5f]\n",
            $elem_href->nat_occ_isots->{$key}->wgt_molar_mass,
            $molar_mass->symbol,
            $elem_href->nat_occ_isots->{$key}->mass_frac,
        );

        print $the_first_half.$the_latter_half;
    }
    printf(
        "%sThe weighted-average molar mass of [%s]: [%.3f %s]\n",
        $disp->indent,
        $elem_href->name,
        $elem_href->wgt_avg_molar_mass,
        $molar_mass->symbol,
    );
    say $disp->border->dash;

    # Notification - ending
    pause_terminal() if $routine->is_verbose;

    return;
}


sub enrich {
    # """Redistribute the mass fractions of isotopes
    # according to the enrichment level of the isotope of interest."""

    my $chem_elem   = shift;
    my $isot_of_int = shift;

    # Notification - beginning
    show_routine_header((caller(0))[3]) if $routine->is_verbose;

    #
    # Arithmetic
    #
    # (i) Variables for a - b = c, where a >= b
    #     a: $to_be_transferred; the amount of mass fraction
    #        to be transferred from Mo isotopes to Mo-100
    #     b: $chem_elem->nat_occ_isots->{$key}->mass_frac;
    #        the mass fraction of of an isotope to be processed
    #     c: $remainder; the one $to_be_transferred will take
    #        after subtraction
    #
    # (ii) Variables for b - a = c, where b > a
    #     b: $chem_elem->nat_occ_isots->{$key}->mass_frac;
    #        the mass fraction of of an isotope to be processed
    #     a: $to_be_transferred; the amount of mass fraction
    #        to be transferred from Mo isotopes to Mo-100
    #     c: $remainder; the one
    #        $chem_elem->nat_occ_isots->{$key}->mass_frac
    #        will take after subtraction
    #
    my $to_be_transferred;
    my $remainder;

    #
    # As the enrichment of a given isotope of a chemical
    # element is by definition the mass fraction of the
    # isotope, the attributes 'enrichment' and 'mass_frac'
    # represent essentially the same quantity.
    #
    # I have introduced the attribute 'enrichment' to
    # calculate new mass fractions when a Mo target is
    # enriched in Mo-100: when an element is enriched
    # in one of its isotopes, the mass fractions of
    # all of its isotopes are changed.
    #
    # To do so, we first predefine the by-mass enrichment
    # to $mo100->enri, which may have been
    # overwritten in overwrite_param(), find the remainder
    # of $mo100->enri and $mo100->mass_frac,
    # add the remainder to $mo100->mass_frac, and subtract
    # the mass fractions of other Mo isotopes from
    # the remainder until the remainder becomes zero.
    #
    # Such subtraction is performed from the lightest
    # Mo isotope to reflect the use of a centrifuge.
    #
    $to_be_transferred = ($isot_of_int->enri) - ($isot_of_int->mass_frac);
    my $i_remember_you  = $to_be_transferred;
    my $you_remember_me = $isot_of_int->mass_frac;

    # Calculation conditions:
    # (1) Current Mo-100 mass fraction and
    # (2) Total mass fraction of other Mo isotopes available
    if ($routine->is_verbose) {
        my $k = 0;
        @{$routine->rpt_arr} = ();
        $routine->rpt_arr->[$k++] = $disp->border->dash;
        $routine->rpt_arr->[$k++] = "Calculation conditions";
        $routine->rpt_arr->[$k++] = $disp->border->dash;
        $routine->rpt_arr->[$k++] = sprintf(
            "%s mass fraction, pre-enrichment: [%.5f]",
            $isot_of_int->symb,
            $isot_of_int->enri,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "%s mass fraction, postenrichment: [%.5f]",
            $isot_of_int->symb,
            $isot_of_int->mass_frac,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "We will now transfer [%.5f] from %s isotopes to %s.",
            $to_be_transferred,
            $chem_elem->symb,
            $isot_of_int->symb,
        );
        $routine->rpt_arr->[$k] = $disp->border->dash;

        for (my $i=0; $i<=$k; $i++) {
            printf(
                "%s%s\n",
                $i !~ /\b[02]|$k\b/ ? $disp->indent : '',
                $routine->rpt_arr->[$i],
            );
        }
    }

    # Redistribute mass fractions.
    foreach my $key (sort keys %{$chem_elem->nat_occ_isots}) {
        # When the total mass fraction of the isotopes to be
        # transferred to Mo-100 is zero, terminate the iteration.
        last if $to_be_transferred == 0;

        # Top border
        say $disp->border->dash if $routine->is_verbose;

        # Notify the current isotope.
        if ($routine->is_verbose) {
            printf
                $disp->indent.
                "Isotope: [%s], mass_frac: [%.5f]\n",
                $key,
                $chem_elem->nat_occ_isots->{$key}->mass_frac;
        }

        # If 'Mo-100' is to be processed,
        # add the available mass fraction to its current mass fraction.
        if ($key eq $isot_of_int->flag) {
            $chem_elem->nat_occ_isots->{$key}->mass_frac(
                $chem_elem->nat_occ_isots->{$key}->mass_frac
                + $to_be_transferred
            );
            if ($routine->is_verbose) {
                printf(
                    $disp->indent.
                    "\"Added\" to [%.5f], its mass_frac became: [%.5f]\n",
                    $to_be_transferred,
                    $isot_of_int->mass_frac,
                );
                say $disp->border->dash;
            }
            next;
        }

        # When the mass fraction of an isotope,
        # except the isotope to be enriched or depleted, is zero,
        # skip to the next isotope.
        if (
            # '$key ne ..' must be placed here to avoid mass_frac not added to
            # $mo100->mass_frac when $mo100->mass_frac starts from zero, which
            # happens when its enrichment has been set to under the natural
            # value (0.10146).
            $key ne $isot_of_int->flag
            and $chem_elem->nat_occ_isots->{$key}->mass_frac == 0
        ) {
            if ($routine->is_verbose) {
                printf(
                    "%sHas no mass fraction to transfer to Mo-100\n",
                    $disp->indent,
                );
                say $disp->border->dash;
            }
            next;
        }

        # (i) a - b = c, where a >= b
        # If the available mass fraction is greater than
        # or equal to the mass fraction of the isotope to be
        # processed, subtract the latter from the former.
        if (
            $to_be_transferred
            >= $chem_elem->nat_occ_isots->{$key}->mass_frac
        ) {
            # Perform c = a - b.
            $remainder
                = $to_be_transferred
                - $chem_elem->nat_occ_isots->{$key}->mass_frac;

            # Perform b = 0.
            $chem_elem->nat_occ_isots->{$key}->mass_frac(0);

            if ($routine->is_verbose) {
                printf(
                    "%s\"Subtracted\" from [%.5f],".
                    " its mass_frac became: [%.5f]\n",
                    $disp->indent,
                    $to_be_transferred,
                    $chem_elem->nat_occ_isots->{$key}->mass_frac
                );
            }

            # Perform a = c.
            $to_be_transferred = $remainder;

            if ($routine->is_verbose) {
                printf(
                    "%s\$to_be_transferred is now: [%.5f]\n",
                    $disp->indent,
                    $to_be_transferred,
                );
            }
        }

        # (ii) b - a = c, where b > a
        # If, on the other hand,
        # the available mass fraction is less than
        # the mass fraction of the isotope to be processed,
        # subtract the former from the latter.
        elsif (
            $to_be_transferred
            < $chem_elem->nat_occ_isots->{$key}->mass_frac
        ) {
            # Perform c = b - a.
            $remainder
                = $chem_elem->nat_occ_isots->{$key}->mass_frac
                - $to_be_transferred;

            # Notify that b is larger than a.
            if ($routine->is_verbose) {
                printf(
                    "%sThe isotope possesses a larger mass fraction, [%.5f],\n",
                    $disp->indent,
                    $chem_elem->nat_occ_isots->{$key}->mass_frac,
                );
                printf(
                    "%sthan the mass fraction to be transferred, [%.5f].\n",
                    $disp->indent,
                    $to_be_transferred,
                );
                printf(
                    "%sHence we now subtract the latter [%.5f]".
                    " from the former [%.5f];\n",
                    $disp->indent,
                    $to_be_transferred,
                    $chem_elem->nat_occ_isots->{$key}->mass_frac,
                );
            }

            # Perform b = c.
            $chem_elem->nat_occ_isots->{$key}->mass_frac( $remainder );

            if ($routine->is_verbose) {
                printf(
                    "%s\\$mo->nat_occ_isots->{$key}->mass_frac: [%.5f]\n",
                    $disp->indent,
                    $chem_elem->nat_occ_isots->{$key}->mass_frac,
                );
            }

            # Perform a = 0.
            $to_be_transferred = 0;
        }
        say $disp->border->dash if $routine->is_verbose;
    }

    # Notification - ending
    if ($routine->is_verbose) {
        my $k = 0;
        @{$routine->rpt_arr} = ();
        $routine->rpt_arr->[$k++] = $disp->border->dash;
        $routine->rpt_arr->[$k++] = sprintf(
            "Transferring [%.5f] to \$mo100->mass_frac [%.5f] completed.",
            $i_remember_you,
            $you_remember_me,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "\$to_be_transferred has become [%.5f].",
            $to_be_transferred,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "\$mo100->mass_frac has become [%.5f].",
            $mo100->mass_frac,
        );
        $routine->rpt_arr->[$k++] =
            "Recalculation of the average molar mass of Mo is necessary;";
        $routine->rpt_arr->[$k++] =
            "calc_elem_wgt_molar_mass_and_isot_mass_fracs() will be called.",
        $routine->rpt_arr->[$k++] =
            "(but now with 'mass_frac' str argument--preventing mass_frac recalc)";
        $routine->rpt_arr->[$k] = $routine->rpt_arr->[0];

        for (my $i=0; $i<=$k; $i++) {
            printf(
                "%s%s\n",
                $i !~ /\b[0]|$k\b/ ? $disp->indent : '',
                $routine->rpt_arr->[$i],
            );
            print "\n" if $i == 3;
        }
    }
    pause_terminal() if $routine->is_verbose;

    return;
}


sub convert_mass_frac_to_amt_frac {
    # """Convert mass fractions to amount fractions."""

    my $chem_elem = shift;

    # Notification - beginning
    show_routine_header((caller(0))[3]) if $routine->is_verbose;

    foreach my $key (keys %{$chem_elem->nat_occ_isots}) {
        $chem_elem->nat_occ_isots->{$key}->amt_frac(
            $chem_elem->nat_occ_isots->{$key}->mass_frac
            * $chem_elem->wgt_avg_molar_mass
            / $chem_elem->nat_occ_isots->{$key}->molar_mass
        );
    }

    if ($routine->is_verbose) {
        my $k = 0;
        @{$routine->rpt_arr} = ();
        $routine->rpt_arr->[$k++] = $disp->border->dash;
        $routine->rpt_arr->[$k++] = sprintf(
            "[%s isotopes]: mass_frac -> amt_frac conversion completed.",
            $chem_elem->symb
        );
        $routine->rpt_arr->[$k++] =
            "show_amt_and_mass_fracs_and_molar_mass() will print the results.",
        $routine->rpt_arr->[$k] = $routine->rpt_arr->[0];

        for (my $i=0; $i<=$k; $i++) {
            printf(
                "%s%s\n",
                $i !~ /\b[0]|$k\b/ ? $disp->indent : '',
                $routine->rpt_arr->[$i],
            );
        }
    }

    # Notification - ending
    pause_terminal() if $routine->is_verbose;
    show_amt_and_mass_fracs_and_molar_mass($chem_elem) if $routine->is_verbose;

    return;
}


sub apply_eff_of_mo_tar_comp {
    # """Apply the effects of Mo target composition."""

    # Notification - beginning
    show_routine_header((caller(0))[3]) if $routine->is_verbose;

    # (1) Define the oxygen-molybdenum mole ratio and the mass density
    #     of the Mo target, which are used for various calculations,
    #     and define the thermal conductivity, and melting and boiling
    #     points of the Mo target, which are used for printing purposes.
    if ($routine->is_verbose) {
        printf(
            "%sProperties of [%s] are being assigned...\n",
            $disp->indent,
            $mo_tar->name,
        );
    }

    $mo->num_moles(1);

    if ($mo_tar->mole_ratio_o_to_mo == 0) {
        $o->num_moles(0);
        $mo_tar->mass_dens(10.28e+6); # g m^-3 at near r.t.
        $mo_tar->therm_cond(138);     # W m^-1 K^-1
        $mo_tar->melt_point(2896.15); # K
        $mo_tar->boil_point(4912.15); # K
    }
    elsif ($mo_tar->mole_ratio_o_to_mo == 2) {
        $o->num_moles(2);
        $mo_tar->mass_dens(6.47e+6);
        $mo_tar->therm_cond(0);
        $mo_tar->melt_point(1370.15);
        $mo_tar->boil_point(0);
    }
    elsif ($mo_tar->mole_ratio_o_to_mo == 3) {
        $o->num_moles(3);
        $mo_tar->mass_dens(4.69e+6);
        $mo_tar->therm_cond(0);
        $mo_tar->melt_point(1068.15);
        $mo_tar->boil_point(1428.15);
    }

    # (2) Calculate the volume of the Mo target and, by multiplying
    #     the volume by its mass density, calculate its mass.
    if ($routine->is_verbose) {
        printf(
            "%sThe volume and mass of [%s] are being\n".
            " calculated by calc_vol_and_mass()...\n",
            $disp->indent,
            $mo_tar->name,
        );
    }
    calc_vol_and_mass($mo_tar);

    if ($routine->is_verbose) {
        my $k = 0;
        my %item_lab = (
            # (key) An index of @{$routine->rpt_arr}
            # (val) An item label
            2 => '1',
            5 => '2',
            6 => '3',
        );
        @{$routine->rpt_arr} = ();
        $routine->rpt_arr->[$k++] = $disp->border->dash;
        $routine->rpt_arr->[$k++] = sprintf(
            "Selected %s target: [%s]",
            $mo->symb,
            $mo_tar->symb,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "Per mole of [%s],",
            $mo_tar->symb,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "the number of moles of [%s] is [%d],",
            $mo->name,
            $mo->num_moles,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "and that of [%s] is [%d].",
            $o->name,
            $o->num_moles,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "The mass density of [%s] is [%g %s].",
            $mo_tar->symb,
            $mo_tar->mass_dens,
            $mass_dens->symb,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "calc_vol_and_mass() calculated the volume of [%s] as:",
            $mo_tar->symb,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "[%g %s], and thereby its mass: [%g %s].",
            $mo_tar->vol,
            $vol->symb,
            $mo_tar->mass,
            $mass->symb,
        );
        $routine->rpt_arr->[$k] = $routine->rpt_arr->[0];

        for (my $i=0; $i<=$k; $i++) {
            print $disp->indent if $i !~ /\b[0]|$k\b/;

            # Insert a hanging indent.
            my $the_len = length ($disp->indent."(1) ") - length $disp->indent;
            print $alignment->symb->bef x $the_len
                if $i !~ /\b[0-2]|[5-6]|$k\b/;

            print "($item_lab{$i}) " if $i =~ /\b[256]\b/;
            say $routine->rpt_arr->[$i];
        }
    }

    # Notification - ending
    pause_terminal() if $routine->is_verbose;

    return;
}


sub calc_molar_mass_of_mo_tar_and_mass_frac_of_mo {
    # """Calculate the new molar mass of the chosen Mo target."""

    # Notification - beginning
    show_routine_header((caller(0))[3]) if $routine->is_verbose;


    # (1/2) Calculate the new molar mass of the chosen Mo target which
    #       has been affected by, if any, Mo-100 enrichment.
    # > apply_eff_of_mo_tar_comp() defines '$mo->num_moles' and
    #   $o->num_moles; this subroutine must thus be called beforehand.
    # > $mo->wgt_avg_molar_mass, on the other hand,
    #   may have been recalculated following Mo-100 enrichment.
    $mo_tar->molar_mass(
        ($mo->num_moles * $mo->wgt_avg_molar_mass)
        + ($o->num_moles * $o->wgt_avg_molar_mass)
    );

    # (2/2) Using the newly calculated molar mass of the Mo target,
    #       calculate the mass fraction of molybdenum in the Mo target.
    $mo->mass_frac(
        ($mo->num_moles * $mo->wgt_avg_molar_mass)
        / $mo_tar->molar_mass
    );

    # The calculated elemental mass fraction of Mo
    if ($routine->is_verbose) {
        my %item_lab = (
            # (key) An index of @{$routine->rpt_arr}
            # (val) An item label
            1 => '1',
            2 => '2',
            3 => '3',
        );

        my $k = 0;
        @{$routine->rpt_arr} = ();
        $routine->rpt_arr->[$k++] = say $disp->border->dash;
        $routine->rpt_arr->[$k++] = sprintf(
            "[%s] molar_mass: [%g %s]",
            $mo_tar->symb,
            $mo_tar->molar_mass,
            $molar_mass->symbol,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "[%s] molar_mass: [%g %s]",
            $mo->symb,
            $mo->wgt_avg_molar_mass,
            $molar_mass->symbol,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "[%s] mass_frac in [%s], or (2) divided by (1): [%.5f].",
            $mo->symb,
            $mo_tar->symb,
            $mo->mass_frac,
        );

        foreach my $j (1..3) {
            $routine->rpt_arr->[$j] = sprintf(
                "%s(%s) %s\n",
                $disp->indent,
                $item_lab{$j},
                $routine->rpt_arr->[$j],
            );
        }

        $routine->rpt_arr->[4] =
        $routine->rpt_arr->[5] =
        $routine->rpt_arr->[6] = "";

        if ($mo_tar->mole_ratio_o_to_mo != 0 and $mo_tar->is_enri) {
            # For nonmetallic Mo targets enriched in Mo-100
            $routine->rpt_arr->[4] = sprintf(
                "At [%s] mass_frac [%g]:",
                $mo100->symb,
                $mo100->mass_frac,
            );
            $routine->rpt_arr->[5] = sprintf(
                "As [%s] is not of metallic, [%s] mass_frac has also",
                $mo_tar->symb,
                $mo100->symb,
            );
            $routine->rpt_arr->[6] =
                "affected (2) and thereby (3).";

            # Modify strings
            my $the_len = length $disp->indent."(1) " - length $disp->indent;
            foreach my $j (4..6) {
                $routine->rpt_arr->[$j] = sprintf(
                    "%s%s%s\n",
                    $disp->indent,
                    $alignment->symb->bef x $the_len,
                    $routine->rpt_arr->[$j],
                );
            }
        }
        $routine->rpt_arr->[7] = $routine->rpt_arr->[0];

        for (my $i=0; $i<=$#{$routine->rpt_arr}; $i++) {
            printf "%s", $routine->rpt_arr->[$i];

            print "\n" if (
                $mo_tar->mole_ratio_o_to_mo != 0
                and $mo_tar->is_enri
                and $i == 3
            );
        }
    }

    # Notification - ending
    pause_terminal() if $routine->is_verbose;

    return;
}


sub calc_mass_and_mass_dens_of_mo_and_mo100 {
    # """Calculate the masses and mass densities of Mo and Mo-100"""

    # Notification - beginning
    show_routine_header((caller(0))[3]) if $routine->is_verbose;

    #
    # Masses
    #

    # Mass of Mo element
    # > Used for Mo-99 specific activity calculation
    # > calc_molar_mass_of_mo_tar_and_mass_frac_of_mo() populates
    #   $mo->mass_frac, and calc_vol_and_mass() populates $mo_tar->mass;
    #   therefore, the two subroutines must be called beforehand.
    $mo->mass(
        $mo->mass_frac #<--calc_molar_mass_of_mo_tar_and_mass_frac_of_mo()
        * $mo_tar->mass #<--calc_vol_and_mass()
    );

    # Mass of Mo-100
    # > calc_elem_wgt_molar_mass_and_isot_mass_fracs() "or"
    #   enrich() populates $mo100->mass_frac;
    #   therefore, one of these subroutines must be called beforehand.
    $mo100->mass(
        # v calc_elem_wgt_molar_mass_and_isot_mass_fracs() or enrich()
        $mo100->mass_frac
        # v Calculated in the above
        * $mo->mass
    );

    #
    # Mass densities
    #

    # Mass density of Mo element
    # > calc_molar_mass_of_mo_tar_and_mass_frac_of_mo() populates
    #   the attribute 'mass_frac' and apply_eff_of_mo_tar_comp() populates
    #   the attribute 'mass_dens'; therefore, the two subroutines
    #   must be called beforehand.
    $mo->mass_dens(
        # v calc_molar_mass_of_mo_tar_and_mass_frac_of_mo()
        $mo->mass_frac
        # v apply_eff_of_mo_tar_comp()
        * $mo_tar->mass_dens
    );

    # Mass density of "Mo-100"
    # calc_elem_wgt_molar_mass_and_isot_mass_fracs()
    # "or" enrich() defines '$mo100->mass_frac';
    # one of these subroutines must therefore be called beforehand.
    $mo100->mass_dens(
        # v calc_elem_wgt_molar_mass_and_isot_mass_fracs() "or" enrich()
        $mo100->mass_frac
        # v Calculated in the above
        * $mo->mass_dens
    );

    if ($routine->is_verbose) {
        my $k = 0;
        @{$routine->rpt_arr} = ();
        $routine->rpt_arr->[$k++] = $disp->border->dash;
        $routine->rpt_arr->[$k++] = sprintf(
            "[%s] mass_frac [%.4f] * [%s] mass      [%.4f %s]          =".
            " [%s] mass      [%.4f %s]",
            $mo->symb,
            $mo->mass_frac,
            $mo_tar->symb,
            $mo_tar->mass,
            $mass->symbol,
            $mo->symb,
            $mo->mass,
            $mass->symbol,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "[%s] mass_frac [%.4f] * [%s] mass_dens [%.3e %s]".
            " = [%s] mass_dens [%.3e %s]",
            $mo->symb,
            $mo->mass_frac,
            $mo_tar->symb,
            $mo_tar->mass_dens,
            $mass_dens->symbol,
            $mo->symb,
            $mo->mass_dens,
            $mass_dens->symbol,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "[%s] mass_frac [%.4f] * [%s] mass      [%.4f %s]          =".
            " [%s] mass      [%.4f %s]",
            $mo100->symb,
            $mo100->mass_frac,
            $mo->symb,
            $mo->mass,
            $mass->symbol,
            $mo100->symb,
            $mo100->mass,
            $mass->symbol,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "[%s] mass_frac [%.4f] * [%s] mass_dens [%.3e %s]".
            " = [%s] mass_dens [%.3e %s]",
            $mo100->symb,
            $mo100->mass_frac,
            $mo->symb,
            $mo->mass_dens,
            $mass_dens->symbol,
            $mo100->symb,
            $mo100->mass_dens,
            $mass_dens->symbol,
        );
        $routine->rpt_arr->[$k] = $routine->rpt_arr->[0];

        for (my $i=0; $i<=$k; $i++) {
            printf(
                "%s%s\n",
                $i !~ /[0]|$k/ ? $disp->indent : '',
                $routine->rpt_arr->[$i],
            );
            print "\n" if $i == 2;
        }
    }

    # Ending
    pause_terminal() if $routine->is_verbose;

    return;
}


sub calc_num_dens {
    # """Calculate the number density of a given nuclide.

    my $nuclide = shift;

    # Notification - beginning
    show_routine_header((caller(0))[3]) if $routine->is_verbose;

    # Calculate the number density.
    $nuclide->num_dens(        # Num of nuclides cm^-3
        $nuclide->mass_dens    # g cm^-3
        * $const->avogadro     # Num of substances mol^-1
        / $nuclide->molar_mass # g mol^-1
    );

    if ($routine->is_verbose) {
        my $conv = '%-'.(length '$const->avogadro').'s';
        my $k = 0;
        @{$routine->rpt_arr} = ();
        $routine->rpt_arr->[$k++] = $disp->border->dash;
        $routine->rpt_arr->[$k++] = sprintf(
            "$conv: [%s]",
            'nuclide',
            $nuclide->symb,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "$conv: [%.3e %s]",
            'mass_dens',
            $nuclide->mass_dens,
            $mass_dens->symbol,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "$conv: [%g %s]",
            'molar_mass',
            $nuclide->molar_mass,
            $molar_mass->symbol,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "$conv: [%g %s]",
            '$const->avogadro',
            $const->avogadro,
            $mol->symbol_recip,
        );
        $routine->rpt_arr->[$k++] = sprintf(
            "$conv: [%g %s]", # Preconversion
            'num_dens',
            $nuclide->num_dens,
            $num_dens->symbol,
        );
        $routine->rpt_arr->[$k] = $disp->border->dash;

        for (my $i=0; $i<=$k; $i++) {
            printf(
                "%s%s\n",
                $i !~ /[0]|$k/ ? $disp->indent : '',
                $routine->rpt_arr->[$i],
            );
        }
    }

    # Ending
    pause_terminal() if $routine->is_verbose;

    return;
}


sub calc_mo100_num_dens {
    # """Calculate the number density of Mo-100."""

    #
    # Notes
    #
    # Depending on the enrichment of Mo-100, the following results:
    # (1) Direct change in the isotopic mass fraction of Mo-100
    #     ($mo100->mass_frac)
    # (2) Deviation of the elemental molar mass of Mo ($mo->wgt_avg_molar_mass)
    #     from its reference value, 95.94 g mol^-1; such a "new" molar mass
    #     of Mo results in a different elemental mass fraction of Mo
    #     when a Mo oxide target is used.
    #
    # Depending on the chemical composition of a Mo target,
    # the following results:
    # (1) Different number of moles of oxygen atoms per mole of a Mo
    #     target and thereby a different elemental mass fraction of Mo
    #     in the target
    # (2) Different compound mass density of the Mo target
    #

    #
    # Calculation order
    #
    # (1) Mass fractions of Mo isotopes following Mo-100 enrichment
    #
    # (a) New mass fractions of Mo isotopes wrt Mo-100 enrichment
    # (b) New average molar mass of Mo using the new mass
    #     fractions of (a)
    # (c) Convert the new mass fractions of Mo isotopes to amount fractions
    #     (for displaying purposes only).
    #
    # Caution: When natural Mo is used ($mo_tar->is_enri == 0),
    #          no mass fraction should be recalculated, therefore
    #          the steps (a)--(c) are all skipped.
    #
    # (d) Mass fraction of Mo (out of a Mo target)
    #

    # (a)--(c)
    if ($mo_tar->is_enri) {
        enrich(
            $mo,
            $mo100,
        );

        calc_elem_wgt_molar_mass_and_isot_mass_fracs(
            $mo,
            'mass_frac', # Caution: Must be 'mass_frac', not 'amt_frac'
        );

        convert_mass_frac_to_amt_frac($mo);
    }

    # (d)
    apply_eff_of_mo_tar_comp();
    calc_molar_mass_of_mo_tar_and_mass_frac_of_mo();

    # (2) Masses and mass densities of Mo and Mo-100
    #     (requires calling apply_eff_of_mo_tar_comp() and
    #     calc_molar_mass_of_mo_tar_and_mass_frac_of_mo() beforehand)
    calc_mass_and_mass_dens_of_mo_and_mo100();

    # (3) Number density of Mo-100
    # > Requires calling the following subroutines beforehand:
    #   apply_eff_of_mo_tar_comp(),
    #   calc_molar_mass_of_mo_tar_and_mass_frac_of_mo(), and
    #   calc_mass_and_mass_dens_of_mo_and_mo100()
    calc_num_dens($mo100);

    if ($routine->is_verbose) {
        my $k = 0;
        @{$routine->rpt_arr} = ();
        $routine->rpt_arr->[$k++] = $disp->border->dash;
        $routine->rpt_arr->[$k++] = sprintf(
            "The calculated number density of [%s]: [%g %s];",
            $mo100->symb,
            $mo100->num_dens,
            $num_dens->symbol,
        );
        $routine->rpt_arr->[$k++] =
            "summary_of_mo100_num_dens_calc() will print the summary.",
        $routine->rpt_arr->[$k] = $routine->rpt_arr->[0];

        for (my $i=0; $i<=$k; $i++) {
            printf(
                "%s%s\n",
                $i !~ /\b[0]|$k\b/ ? $disp->indent : '',
                $routine->rpt_arr->[$i],
            );
        }
    }

    # Notification - ending
    pause_terminal() if $routine->is_verbose;
    summary_of_mo100_num_dens_calc() if $routine->is_verbose;

    return;
}


sub summary_of_mo100_num_dens_calc {
    # """Show the summary of Mo-100 number density calculation."""

    # Notification - beginning
    show_routine_header((caller(0))[3]) if $routine->is_verbose;

    my %eq_lab = (
        # (key) An index of @{$routine->rpt_arr}
        # (val)  An equation label
        2  => '1',
        3  => '2',
        4  => '3',
        5  => '4',
        6  => '5',
        8  => '6',
        10 => '7',
    );

    my $k = 0;
    @{$routine->rpt_arr} = ();
    $routine->rpt_arr->[$k++] = $disp->border->dash;
    $routine->rpt_arr->[$k++] = sprintf(
        "%s target: [%s]",
        $mo->symb,
        $mo_tar->symb,
    );
    $routine->rpt_arr->[$k++] = sprintf(
        "=> Mass density of [%s]: [%g g m^-3]",
        $mo_tar->symb,
        $mo_tar->mass_dens,
    );
    $routine->rpt_arr->[$k++] = sprintf(
        "=> Mass fraction of [%s] in [%s]: [%g]",
        $mo->symb,
        $mo_tar->symb,
        $mo->mass_frac,
    );
    $routine->rpt_arr->[$k++] = sprintf(
        "=> Mass density of [%s], or (1)*(2): [%g g m^-3]",
        $mo->symb,
        $mo->mass_dens,
    );
    $routine->rpt_arr->[$k++] = sprintf(
        "Mass fraction (enrichment) of [%s]: [%g]",
        $mo100->symb,
        $mo100->mass_frac,
    );
    $routine->rpt_arr->[$k++] = sprintf(
        "=> Mass density of [%s], or (3)*(4): [%g g m^-3]",
        $mo100->symb,
        $mo100->mass_dens,
    );
    $routine->rpt_arr->[$k++] = sprintf(
        "The product of (5) and the Avogadro constant [%g %s]",
        $const->avogadro,
        $mol->symb_recip,
    );
    $routine->rpt_arr->[$k++] = sprintf(
        "divided by the molar mass of [%s], [%g g mol^-1],",
        $mo100->symb,
        $mo100->molar_mass,
    );
    $routine->rpt_arr->[$k++] = sprintf(
        "is the number density of [%s]",
        $mo100->symb,
    );
    $routine->rpt_arr->[$k++] = sprintf(
        "in [%s]: [%g m^-3]",
        $mo_tar->symb,
        $mo100->num_dens,
    );
    $routine->rpt_arr->[$k] = $routine->rpt_arr->[0];

    for (my $i=0; $i<=$k; $i++) {
        printf(
            "%s%s",
            $i !~ /\b[0]|$k\b/ ? $disp->indent : '',
            $routine->rpt_arr->[$i],
        );

        if ($i =~ /\b[2-6]|8|10\b/) {
            calc_alignment_symb_len(
                $routine->rpt_arr->[$i],
                (
                    length($routine->rpt_arr->[0])
                    - length($disp->indent)
                    - length("... (1)")
                ),
                'ragged',
            );

            print $alignment->symb->aft x $alignment->symb->len;
            printf "... (%d)", $eq_lab{$i};
        }
        print "\n";
        print "\n" if $i =~ /\b[46]\b/;
    }

    # Notification - ending
    pause_terminal() if $routine->is_verbose;

    return;
}


sub convert_units {
    # """Convert units using ${<unit_obj>}->factor."""

    #
    # For those calculated in calc_mo100_num_dens()
    #
    my %to_be_converted = (
        t_tot => {
            obj   => $t_tot,
            attrs => [qw/from to/],
        },
        t_irr => {
            obj   => $t_irr,
            attrs => [qw/from to/],
        },
        t_dec => {
            obj   => $t_dec,
            attrs => [qw/from to/],
        },
        t_pro => {
            obj   => $t_pro,
            attrs => [qw/from to/],
        },
        t_del => {
            obj   => $t_del,
            attrs => [qw/from to/],
        },
        chem_proc_time_required => {
            obj   => $chem_proc->time_required,
            attrs => [qw/to/],
        },
        tc99m_gen_delivery_time => {
            obj   => $tc99m_gen->delivery_time,
            attrs => [qw/to/],
        },
        const => {
            obj   => $const,
            attrs => [qw/avogadro/],
        },
        w => {
            obj   => $w,
            attrs => [qw/wgt_avg_molar_mass mass mass_dens num_dens/],
        },
        o => {
            obj   => $o,
            attrs => [qw/wgt_avg_molar_mass mass mass_dens num_dens/],
        },
        mo => {
            obj   => $mo,
            attrs => [qw/wgt_avg_molar_mass mass mass_dens num_dens/],
        },
        mo99 => {
            obj   => $mo99,
            attrs => [qw/half_life_phy/],
        },
        mo100 => {
            obj   => $mo100,
            attrs => [qw/molar_mass mass mass_dens num_dens/],
        },
        tc => {
            obj   => $tc,
            attrs => [qw/wgt_avg_molar_mass mass mass_dens num_dens/],
        },
        tc99m => {
            obj   => $tc99m,
            attrs => [qw/half_life_phy avg_dose/],
        },
        converter => {
            obj   => $converter,
            attrs => [qw/
                molar_mass
                mass
                mass_dens
                num_dens
                vol
                therm_cond
                melt_point
                boil_point
            /],
        },
        converter_geom => {
            obj   => $converter->geom,
            attrs => [qw/rad1/],
        },
        mo_tar => {
            obj   => $mo_tar,
            attrs => [qw/
                molar_mass
                mass
                mass_dens
                num_dens
                vol
                therm_cond
                melt_point
                boil_point
            /],
        },
        mo_tar_geom => {
            obj   => $mo_tar->geom,
            attrs => [qw/rad1 rad2 hgt/],
        },
    );

    foreach my $k1 (keys %to_be_converted) {
        # Redirection
        my $obj        = $to_be_converted{$k1}{obj};
        my $attrs_aref = $to_be_converted{$k1}{attrs};

        foreach my $attr (@{$attrs_aref}) {
            my($op, $fac);

            if ($attr =~ /\bfrom|to|half_life_phy\b/i) {
                $op  = 'div',
                $fac = $time->factor,
            }
            if ($attr =~ /\bavg_dose\b/i) {
                $op  = 'div',
                $fac = $act->factor,
            }
            if ($attr =~ /\bavogadro\b/i) {
                $op  = 'mul',
                $fac = $mol->factor,
            }
            if ($attr =~ /\b(?:wgt_avg_)?molar_mass\b/i) {
                $op  = 'mul',
                $fac = $molar_mass->factor,
            }
            if ($attr =~ /\bmass\b/i) {
                $op  = 'div',
                $fac = $mass->factor,
            }
            if ($attr =~ /\bmass_dens\b/i) {
                $op  = 'mul',
                $fac = $mass_dens->factor,
            }
            if ($attr =~ /\bnum_dens\b/i) {
                $op  = 'mul',
                $fac = $num_dens->factor,
            }
            if ($attr =~ /\brad[12]|hgt\b/i) {
                $op  = 'div',
                $fac = $len->factor,
            }
            if ($attr =~ /\bvol\b/i) {
                $op  = 'div',
                $fac = $vol->factor,
            }
            if ($attr =~ /\btherm_cond\b/i) {
                $op  = 'mul',
                $fac = $therm_cond->factor,
            }
            if ($attr =~ /\b(?:melt|boil)_point\b/i) {
                $op  = 'add',
                $fac = $temp->factor,
            }

            next if not $obj->$attr;
            $obj->$attr($obj->$attr * $fac) if $op =~ /mul/i;
            $obj->$attr($obj->$attr / $fac) if $op =~ /div/i;
            $obj->$attr($obj->$attr + $fac) if $op =~ /add/i;
        }
    }

    #
    # For those calculated in calc_mo99_tc99m_actdyn_data()
    #
    foreach my $_nrg (@{$actdyn->nrgs_of_int}) {
        foreach (
            $mo99->act->sat_arr,
            $mo99->sp_act->sat_arr,
            $mo99->act->irr_arr,
            $mo99->sp_act->irr_arr,
            $mo99->act->dec_arr,
            $mo99->sp_act->dec_arr,
            $tc99m->act->irr_arr,
            $tc99m->act->dec_arr,
            $tc99m->act->elu_arr,
        ) {
            $_ /= $act->factor for @{$_->[$_nrg]};
        }

        $tc99m->act->elu_tot_arr->[$_nrg] /= $act->factor;
    }

    return;
}


sub read_in_micro_xs {
    # """Read in micro cross section data expressed in cm^2."""

    # Notification - beginning
    show_routine_header((caller(0))[3]) if $routine->is_verbose;

    open my $inp_micro_cs_fh, '<', $xs->inp;
    foreach (<$inp_micro_cs_fh>) {
        chomp;
        next if /^#/;
        push @{$xs->micro}, $_ if /^[\d]+/;
    }
    close $inp_micro_cs_fh;

    if ($routine->is_verbose) {
        say $disp->border->dash;
        printf(
            "%s[%s] has been read in to \@{\$xs->micro}.\n",
            $disp->indent,
            $xs->inp,
        );

        if ($xs->is_chk) {
            my @idx_chk = (0, 10, 100, 1000, $#{$xs->micro});
            foreach (@idx_chk) {
                printf(
                    "%s\$xs->{micro}[%4d] contains %.4e cm^2\n",
                    $disp->indent,
                    $_,
                    $xs->micro->[$_],
                );
            }
        }
        say $disp->border->dash;
    }

    # Notification - ending
    pause_terminal() if $routine->is_verbose;

    return;
}


sub calc_mo99_tc99m_actdyn_data {
    # """Calculate Mo-99/Tc-99m activity dynamics data."""

    # y/n prompt
    my $yn_msg = sprintf("%sRun? [y/n]> ", $disp->indent);
    print $yn_msg;
    while (chomp(my $yn = <STDIN>)) {
        last if $yn =~ /\by\b/i;
        return if $yn =~ /\bn\b/i;
        print $yn_msg;
    }
    $actdyn->is_run(1);

    print " Calculation in progress..." if not $routine->is_verbose;
    print "\n";

    # (1/2) Read in microscopic cross section data.
    read_in_micro_xs();

    # (2/2) Read in photon fluence data.
    state $is_first = 1;
    foreach my $_nrg (@{$actdyn->nrgs_of_int}) {
        # Initializations
        @{$actdyn->pwm->pointwise} = (); # Cumul sum
        $actdyn->pwm->gross(0);          # Cumul sum
        # The idx below is the beginning index of @{$xs->micro}
        # read in by ()read_in_micro_xs, which must be initialized to 0
        # at every $_nrg.
        $xs->idx(0);

        # arefs nested to beam energies
        # > Used later for writing datasets to gnuplot files.
        $_->[$_nrg] = [] for (
            $mo99->act->sat_arr,
            $mo99->sp_act->sat_arr,
            $mo99->act->irr_arr,
            $mo99->sp_act->irr_arr,
            $mo99->act->ratio_irr_to_sat_arr,
            $mo99->act->dec_arr,
            $mo99->sp_act->dec_arr,
            $tc99m->act->irr_arr,
            $tc99m->act->dec_arr,
            $tc99m->act->elu_arr,
        );

        #
        # Activity calculation term (1/3)
        # > Pointwise multiplication (PWM): Multiplication of a Monte Carlo
        #   bremsstrahlung fluence by the energy-corresponding micro
        #   cross section under the integral sign, giving rise to
        #   a pointwise product (PWP) expressed in particle^-1.
        # > The terms outside the integral must be multiplied later by the PWPs.
        #

        # PHITS track-eng files labeled with beam energies
        # e.g. tar_e20_spt.ang, tar_e21_spt.ang, ...
        $actdyn->phits->ang(
            $phits->path.
            $phits->bname.
            $_nrg.#<--Control var
            $phits->flag->spectrum.
            '.'.
            $phits->ext->ang
        );

        open my $ang_fh, '<', $actdyn->phits->ang;
        foreach (<$ang_fh>) {
            chomp;

            # Store photon fluences into @col
            if (/^[\s]+[\d]+/) {
                # $col[0]: An empty value (not undef)
                # $col[1]: e-lower
                # $col[2]: e-upper
                # $col[3]: electron
                # $col[4]: r.err
                # $col[5]: photon<-- photon fluence
                # $col[6]: r.err
                # $col[7]: neutron
                # $col[8]: r.err
                my @col = split /[\s]+/;
                $phits->flues->[$xs->idx] = $col[5];

                # Multiply a photon fluence expressed in cm^-2 particle^-1
                # by the energy-corresponding microscopic cross section
                # expressed in cm^2. The resulting product will then have
                # a dimension of particle^-1.
                # As is reused throughout the iteration, the array
                # @{$actdyn->pwm->pointwise} must be initialized at every $_nrg.
                $actdyn->pwm->pointwise->[$xs->idx] =
                    $phits->flues->[$xs->idx]
                    * $xs->micro->[$xs->idx];

                # Move on to the next photon energy index.
                $xs->idx($xs->idx + 1);
            }

            # Skip comments and unnecessary lines.
            else { next }
        }
        close $ang_fh;

        # Sum up all the elements of @{$actdyn->pwm->pointwise} and store
        # the products into $actdyn->pwm->gross.
        # > The use of @{$actdyn->pwm->pointwise} is to check the PWPs,
        #   controlled via $actdyn->pwm->is_chk.
        # > As is reused throughout the iteration, the scalar attribute
        #   $actdyn->pwm->gross must be initialized at every $_nrg.
        $actdyn->pwm->gross($actdyn->pwm->gross + $_)
            for @{$actdyn->pwm->pointwise};

        # PWM check file
        if ($actdyn->pwm->is_chk) {
            if ($is_first) {
                $actdyn->pwm->chk(
                    $actdyn->path.
                    $actdyn->bname.
                    '_'.
                    $actdyn->flag->chk.
                    '.'.
                    $actdyn->ext->chk
                );
                mkdir $actdyn->path if not -e $actdyn->path;
                unlink $actdyn->pwm->chk if -e $actdyn->pwm->chk;
            }

            open my $pwm_chk_fh, '>>:encoding(UTF-8)', $actdyn->pwm->chk;
            select($pwm_chk_fh);

            # Header
            say $gp->cmt_border->dash;
            printf(
                "%s At [%d %s], \@{\$actdyn->pwm->pointwise} contains\n",
                $gp->cmt_symb,
                $_nrg,
                $nrg->symb,
            );
            my $col_header_sep =
                $gp->col->content_sep eq $symb->comma ?
                    $gp->col->content_sep :
                $gp->col->content_sep eq $symb->tab ?
                    $gp->col->content_sep :
                    $gp->col->header_sep;
            printf(
                "%s %s%s%s%s%s\n",
                $gp->cmt_symb,
                'Photon fluence (cm^-2 electron^-1)',
                $col_header_sep,
                'Microscopic xs (cm^2)',
                $col_header_sep,
                'Pointwise product (electron^-1)',
            );
            say $gp->cmt_border->dash;

            # Data
            for (my $i=0; $i<=$#{$actdyn->pwm->pointwise}; $i++) {
                printf(
                    "%5e%s%11e%s%.5e\n",
                    $phits->flues->[$i],
                    $gp->col->content_sep,
                    $xs->micro->[$i],
                    $gp->col->content_sep,
                    $actdyn->pwm->pointwise->[$i],
                );

                print "\n" if $i == $#{$actdyn->pwm->pointwise};
            }

            # Insert one blank line indicating the end of a gnuplot data block,
            # and mark the end of the gnuplot data file.
            print $_nrg != $actdyn->nrgs_of_int->[-1] ?
                $gp->end_of->block : $gp->end_of->file;

            select(STDOUT);
            close $pwm_chk_fh;

            notify_file_gen($actdyn->pwm->chk) if $is_first;

            $is_first = 0;
        }

        # Display $actdyn->pwm->gross at each beam energy in real time.
        if (
            $actdyn->pwm->is_show_gross
            and $routine->is_verbose
        ) {
            printf(
                "%s\$actdyn->pwm->gross at ",
                "%d %s: %.5e per incident electron\n",
                $disp->indent,
                $_nrg,
                $nrg->symb,
                $actdyn->pwm->gross,
            );
            # If the Mo-99 activity is not displayed following its PWP,
            # remind the user of the meaning of PWP.
            if (
                $_nrg == $actdyn->nrgs_of_int->[-1]
                and $routine->is_verbose
                and not $mo99_act_nrg_tirr->is_calc_disp
            ) {
                my $k = 0;
                @{$routine->rpt_arr} = ();
                $routine->rpt_arr->[$k++] = $disp->border->warning;
                $routine->rpt_arr->[$k++] =
                    "The pointwise products above are yet to be activities";
                $routine->rpt_arr->[$k++] =
                    " before multiplied by the outside-integral terms.";
                $routine->rpt_arr->[$k++] =
                    " To print the Mo-99 activities on the terminal,";
                $routine->rpt_arr->[$k++] =
                    " set \$mo99_act_nrg_tirr->is_calc_disp(1)";
                $routine->rpt_arr->[$k++] = $routine->rpt_arr->[0];

                for (my $i=0; $i<=$k; $i++) {
                    printf(
                        "%s%s\n",
                        $i !~ /\b[0]|$k\b/ ? $disp->indent : '',
                        $routine->rpt_arr->[$i],
                    );
                }
            }
        }

        #
        # Activity calculation term (2/3)
        # > Reaction rate
        #
        $actdyn->rrate(
            ($mo_tar->vol * $mo100->num_dens)
            * 1e-6                # uA; num coulombs/second
            * $const->coulomb     # Num electrons/Coulomb
            * $actdyn->pwm->gross #<--Obtained in (1/3) above
        );

        #
        # Activity calculation term (3/3)
        # > Time-dependent quantities
        # > The subroutine fix_time_frames() must be performed beforehand
        #   to correct the interdependent time frames, all of which depend
        #   on $t_irr->to, the end of irradiation: this is because $t_irr->to
        #   could be overwritten by the subroutine overwrite_param().
        # > Therefore, a command calling fix_time_frames() has been placed
        #   immediately after the command calling overwrite_param().

        #
        # Initializations
        #

        # Decay time, beginning
        # > Must be performed at each $_nrg
        # > "Incremented" at $t >= $t_irr->to (greater than or equal to the EOI)
        $t_dec->from(0);
        # Elution ordinal count
        # > Must be performed at each $_nrg
        # > "incremented" at ($t > $t_del->to) % $tc99m_gen->elu_itv == 0
        # > e.g. 96, 120, 144, ...
        $tc99m_gen->elu_ord_count(1);
        # Elution time, beginning
        # > "Incremented" at $t > $t_del->to (greater than the EOD)
        # > For the first Tc-99m eluate; subsequent initialization will be
        #   performed at each ($t > $t_del->to) % $tc99m_gen->elu_itv == 0.
        # > e.g. 96, 120, 144, ...
        $t_elu->from(1);

        foreach my $t ($t_tot->from..$t_tot->to) {
            # Mo-99 saturation activity
            $mo99->act->sat($actdyn->rrate);
            $mo99->sp_act->sat($mo99->act->sat / $mo->mass);
            $mo99->act->sat_arr->[$_nrg][$t]    = $mo99->act->sat;
            $mo99->sp_act->sat_arr->[$_nrg][$t] = $mo99->sp_act->sat;

            # Mo-99 activity
            $mo99->act->irr(
                $mo99->act->sat
                * (1 - exp(-$mo99->dec_const * $t))
            );
            $mo99->sp_act->irr($mo99->act->irr / $mo->mass);
            $mo99->act->irr_arr->[$_nrg][$t]    = $mo99->act->irr;
            $mo99->sp_act->irr_arr->[$_nrg][$t] = $mo99->sp_act->irr;

            # Calculation check display
            if (
                $t == $t_irr->to
                and $routine->is_verbose
                and $mo99_act_nrg_tirr->is_calc_disp
            ) {
                printf(
                    "%s\$mo99->act->irr at %d %s and".
                    " %g-%s irr: ",
                    $disp->indent,
                    $_nrg,
                    $nrg->symb,
                    $t_irr->to,
                    $time->name,
                );
                printf(
                    "%.3f %s/%d-%s\n",
                    $mo99->act->irr_arr->[$_nrg][$t],
                    $act->symbol,
                    $linac->op_avg_beam_curr,
                    $curr->symb,
                );
            }

            # Ratio between Mo-99 activity and Mo-99 saturation activity
            $mo99->act->ratio_irr_to_sat_arr->[$_nrg][$t] =
                $mo99->act->irr / $mo99->act->sat;

            # Tc-99m Activity
            $tc99m->act->irr(
                $mo99->negatron_dec_2->branching_fraction * (
                    1 + (
                        $tc99m->dec_const
                        / ($mo99->dec_const - $tc99m->dec_const)
                        * exp(-$mo99->dec_const * $t)
                    ) + (
                        $mo99->dec_const
                        / ($tc99m->dec_const - $mo99->dec_const)
                        * exp(-$tc99m->dec_const * $t)
                    )
                )
                * $actdyn->rrate
            );
            $tc99m->act->irr_arr->[$_nrg][$t] = $tc99m->act->irr;

            # Mo-99 decay activity
            # (i) Before the EOI: NaN
            if ($t < $t_irr->to) { # e.g. $t < 72
                $mo99->act->dec_arr->[$_nrg][$t] =
                    $mo99->act->dec($gp->missing_dat_str);
                $mo99->sp_act->dec_arr->[$_nrg][$t] =
                    $mo99->sp_act->dec($gp->missing_dat_str);
            }
            # (ii) From the EOI
            elsif ($t >= $t_irr->to) { # e.g. $t >= 72
                $mo99->act->dec(
                    $mo99->act->irr_arr->[$_nrg][$t_irr->to] # EOI
                    # $t_dec->from: 0, 1, 2, ...
                    * exp(-$mo99->dec_const * $t_dec->from)
                );
                # (iii) From the end of chemical processing (EOP)
                # > Reduce the decay activity of Mo-99 by
                #   $chem_proc->mo99_loss_ratio_at_eop
                if ($t >= $t_pro->to) { # e.g. $t >= 84
                    $mo99->act->dec(
                        $mo99->act->dec
                        * (1 - $chem_proc->mo99_loss_ratio_at_eop)
                    );
                }

                # Mo-99 specific decay activity
                $mo99->sp_act->dec($mo99->act->dec / $mo->mass);

                # Storage
                $mo99->act->dec_arr->[$_nrg][$t]    = $mo99->act->dec;
                $mo99->sp_act->dec_arr->[$_nrg][$t] = $mo99->sp_act->dec;
            }

            # Tc-99m decay activity and elution activity
            # (i) Before the EOI: NaN
            if ($t < $t_irr->to) { # e.g. $t < 72
                # Decay activity
                $tc99m->act->dec_arr->[$_nrg][$t] =
                    $tc99m->act->dec($gp->missing_dat_str);

                # Elution activity
                $tc99m->act->elu_arr->[$_nrg][$t] =
                    $tc99m->act->elu($gp->missing_dat_str);
            }
            # (ii) From the EOI
            elsif ($t >= $t_irr->to) { # e.g. $t >= 72
                # (iii) From the EOI to the end of delivery (EOD)
                if ($t <= $t_del->to) { # e.g. $t <= 96
                    $tc99m->act->dec(
                        # Terms signifying the decay of Tc-99m
                        $tc99m->act->irr_arr->[$_nrg][$t_irr->to]
                        * exp(-$tc99m->dec_const * $t_dec->from)

                        # Terms signifying the production of Tc-99m
                        # by the negatron decay of Mo-99
                        + $mo99->negatron_dec_2->branching_fraction
                        * (
                            (
                                $tc99m->dec_const
                                / ($tc99m->dec_const - $mo99->dec_const)
                            )
                            * $mo99->act->irr_arr->[$_nrg][$t_irr->to]
                            * (
                                exp(-$mo99->dec_const * $t_dec->from)
                                - exp(-$tc99m->dec_const * $t_dec->from)
                            )
                        )
                    );

                    # Elution activity
                    $tc99m->act->elu_arr->[$_nrg][$t] =
                        $tc99m->act->elu($gp->missing_dat_str);
                }

                # (iv) From the end of chemical processing (EOP)
                # > Reduce the decay activities of Tc-99m by
                #   $chem_proc->tc99m_loss_ratio_at_eop.
                # > Currently set to be the same as
                #   $chem_proc->mo99_loss_ratio_at_eop.
                if ($t >= $t_pro->to) { # e.g. $t >= 84
                    $tc99m->act->dec(
                        $tc99m->act->dec
                        * (1 - $chem_proc->tc99m_loss_ratio_at_eop)
                    );
                }

                # (v) At the EOD
                # > Reduce the Tc-99m decay activity by
                #   (1 - $tc99m_gen->elu_eff)
                if ($t == $t_del->to) { # e.g. $t == 96
                    # Tc-99m elute
                    $tc99m->act->elu($tc99m->act->dec * $tc99m_gen->elu_eff);

                    # Remnant Tc-99m activity that boosts
                    # its growth toward the Mo-99 activity
                    # > Later stored into
                    #   $tc99m->act->dec_arr->[$_nrg][$t_del->to]
                    $tc99m->act->dec(
                        $tc99m->act->dec - $tc99m->act->elu
                    );

                    # Increment the elution ordinal count from 1 to 2.
                    $tc99m_gen->elu_ord_count($tc99m_gen->elu_ord_count + 1);
                }

                # After the EOD
                if ($t > $t_del->to) { # e.g. $t > 96
                    $tc99m->act->dec(
                        # Terms signifying the decay of Tc-99m
                        $tc99m->act->dec_arr->[$_nrg][
                            # 96
                            $t_del->to + (
                                # 0, 1, 2, ...
                                ($tc99m_gen->elu_ord_count - 2)
                                # 0*24, 1*24, 2*24, ...
                                * $tc99m_gen->elu_itv
                            )
                        ] # 96, 120, 144, ...
                        * exp(-$tc99m->dec_const * $t_elu->from)

                        # Terms signifying the production of
                        # Tc-99m by the negatron decay of Mo-99
                        + $mo99->negatron_dec_2->branching_fraction * (
                            (
                                $tc99m->dec_const
                                / ($tc99m->dec_const - $mo99->dec_const)
                            ) * (
                                $mo99->act->dec_arr->[$_nrg][
                                    # 96
                                    $t_del->to
                                    + (
                                        # 0, 1, ...
                                        ($tc99m_gen->elu_ord_count - 2)
                                        # 0*24, 1*24, ...
                                        * $tc99m_gen->elu_itv
                                    )
                                ] # 96, 120, ...
                            )
                            * (
                                exp(-$mo99->dec_const * $t_elu->from)
                                - exp(-$tc99m->dec_const * $t_elu->from)
                            )
                        )
                    );

                    # Increment the elution time.
                    $t_elu->from($t_elu->from + 1);

                    #'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
                    # Condition 1
                    # > When the time after the arrival of Tc-99m generators
                    #   in radiopharmacies is an integer multiple of the elution
                    #   interval; e.g. $t == 120, 144, ...
                    #
                    # Condition 2
                    # > $tc99m_gen->elu_ord_count < 11
                    # > The conditional will then be bool-true
                    #   until $tc99m_gen->elu_ord_count == 10,
                    #   where $tc99m_gen->elu_ord_count eventually becomes 11
                    #   by the increment in the expression.
                    #'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
                    if (
                        #-------------------------------------------------------
                        # 1st row: $t
                        # 2nd row: $tc99m_gen->elu_ord_count
                        #-------------------------------------------------------
                        # 120,    144,    168,    192,    216,
                        #   2->3,   3->4,   4->5,   5->6,   6->7,
                        # 240,    264,    288,     312,      336
                        #   7->8,   8->9,   9->10,  10->11,   11->12
                        #-------------------------------------------------------
                        ($t - $t_del->to) % $tc99m_gen->elu_itv == 0
                        and $tc99m_gen->elu_ord_count <= $tc99m_gen->elu_ord_to
                    ) {
                        # Tc-99m elute
                        $tc99m->act->elu(
                            $tc99m->act->dec
                            * $tc99m_gen->elu_eff
                        );

                        # Define the remnant Tc-99m activity that boosts
                        # its growth toward the Mo-99 activity.
                        # > Later stored into
                        #   $tc99m->act->dec_arr->[$_nrg][$t_del->to].
                        $tc99m->act->dec(
                            $tc99m->act->dec - $tc99m->act->elu
                        );

                        # Increment the elution ordinal count.
                        $tc99m_gen->elu_ord_count(
                            $tc99m_gen->elu_ord_count
                            + 1
                        );

                        # Initialize the beginning elution time
                        # so that it can again result in 1..24.
                        $t_elu->from(1);
                    }
                }

                # Storage
                $tc99m->act->dec_arr->[$_nrg][$t] = $tc99m->act->dec;
                $tc99m->act->elu_arr->[$_nrg][$t] = $tc99m->act->elu;

                #'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
                # Elution activity of Tc-99m
                # > When the time after the arrival of Tc-99m generators
                #   in radiopharmacies is "NOT" an integer multiple of
                #   the elution interval "OR" the time exceeds the sum of
                #   the time up to the radiopharmacies and the shelf-life
                #   of the Tc-99m generators, overwrite the elution activity
                #   by NaN.
                #'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
                if (
                    ($t - $t_del->to) % $tc99m_gen->elu_itv != 0
                    or $t > ($t_del->to + $tc99m_gen->shelf_life)
                ) {
                    $tc99m->act->elu_arr->[$_nrg][$t] =
                        $gp->missing_dat_str;
                }

                # Increment the decay time.
                # > !! Applies also to the Mo-99 decay activities !!
                # > Must be initialized at every beginning of $_nrg.
                if ($t_dec->from <= $t_dec->to) {
                    $t_dec->from($t_dec->from + 1);
                }
            }
        }

        # Calculate the total activity of Tc-99m eluates.
        foreach (@{$tc99m->act->elu_arr->[$_nrg]}) {
            # Skip NaN and obtain a cumulative sum.
            if (/[0-9]+/) {
                $tc99m->act->elu_tot_arr->[$_nrg] += $_;
            }
        }

        # If specified by the user, discard the activity of
        # the first Tc-99m eluate, which contains the ground state Tc-99.
        if ($tc99m_gen->elu_ord_from != 1) {
            $tc99m->act->elu_tot_arr->[$_nrg]
                -= $tc99m->act->elu_arr->[$_nrg][$t_del->to];
        }
    }

    # Remove an existing PWM check file if it were not to be generated.
    unlink $actdyn->pwm->chk if $actdyn->pwm->is_chk == 0;

    printf(
        "%sActivity dynamics calculation completed.\n",
        $disp->indent,
    );

    return;
}


sub gen_mo99_tc99m_actdyn_data {
    # """Write the calculated Mo-99/Tc-99m activity dynamics data to files."""

    my $prog_info_href = shift;

    # Define fnames of 'actdyn' objects
    define_fnames_for_actdyn_obj();

    # Excel object
    my $mo99_tc99m_actdyn_wb =
        Excel::Writer::XLSX->new($mo99_tc99m_actdyn->excel->xlsx);
    my $mo99_tc99m_actdyn_ws =
        $mo99_tc99m_actdyn_wb->add_worksheet();
    my($row, $col) = (0, 0);
    $mo99_tc99m_actdyn_ws->set_column('A:Z', 14); # Column width
    # Add cell formats
    my %cell_font1 = (
        font => 'Arial',
        size => '11',
    );
    my %shading1 = (
        bg_color => 'yellow',
        bold     => 1,
    );
    my %alignment1 = (
        text_wrap => '1',
        valign    => 'vcenter',
    );
    my $cell_form_dflt =
        $mo99_tc99m_actdyn_wb->add_format(%cell_font1);
    my $cell_form_emph =
        $mo99_tc99m_actdyn_wb->add_format(%cell_font1, %shading1);
    my $cell_form_head =
        $mo99_tc99m_actdyn_wb->add_format(%cell_font1, %alignment1);
    open my $gp_dat1_fh, '>:encoding(UTF-8)', $mo99_act_nrg_tirr->gp->dat;
    open my $gp_dat2_fh, '>:encoding(UTF-8)', $mo99_act_nrg->gp->dat;
    open my $gp_dat3_fh, '>:encoding(UTF-8)', $mo99_tc99m_actdyn->gp->dat;

    #
    # Comment section
    #

    # Front matter
    my $k = 0;
    @{$gp->file_header->info} = ();
    $gp->file_header->info->[$k++] = $gp->cmt_border->plus;
    $gp->file_header->info->[$k++] = sprintf(
        "Activity and specific activity of %s as functions of",
        $mo99->symb,
    );
    $gp->file_header->info->[$k++] = "beam energy and irradiation time";
    $gp->file_header->info->[$k++] = sprintf(
        "Calculated by %s %s",
        $prog_info_href->{titl},
        $prog_info_href->{vers},
    );
    $gp->file_header->info->[$k++] = sprintf(
        "%s <%s>",
        $prog_info_href->{auth}{name},
        $prog_info_href->{auth}{mail},
    );
    create_timestamp();
    $gp->file_header->info->[$k++] = $disp->timestamp->where_month_is_named;
    $gp->file_header->info->[$k] = $gp->file_header->info->[0];

    for (my $i=0; $i<=$k; $i++) {
        # Centering
        if ($i !~ /\b[0]|$k\b/) {
            calc_alignment_symb_len(
                $gp->file_header->info->[$i],
                length $gp->file_header->info->[0],
                'centered',
            );
            $gp->file_header->info->[$i] =
                ($alignment->symb->bef x $alignment->symb->len).
                $gp->file_header->info->[$i];
        }
        $gp->file_header->info->[$i] = sprintf(
            "%s%s",
            $i !~ /\b[0]|$k\b/ ? $gp->cmt_symb.' ' : '',
            $gp->file_header->info->[$i],
        );

        if ($i == 1) {
            say $gp_dat1_fh $gp->file_header->info->[$i];
            say $gp_dat2_fh $gp->file_header->info->[$i];
            my $gp_dat3_new1 = sprintf(
                "%s/%s activity dynamics from targetry irradiation\n",
                $mo99->symb,
                $tc99m->symb,
            );
            calc_alignment_symb_len(
                $gp_dat3_new1,
                length $gp->file_header->info->[0],
                'centered',
            );
            $gp_dat3_new1 = sprintf(
                "%s%s%s",
                $gp->cmt_symb,
                $alignment->symb->bef x $alignment->symb->len,
                $gp_dat3_new1,
            );
            print $gp_dat3_fh $gp_dat3_new1;
            $mo99_tc99m_actdyn_ws->write(
                $row++,
                $col,
                $gp_dat3_new1,
                $cell_form_dflt,
            );
        }

        elsif ($i == 2) {
            say $gp_dat1_fh $gp->file_header->info->[$i];
            say $gp_dat2_fh $gp->file_header->info->[$i];
            my $gp_dat3_new1 = sprintf(
                "to arrival of %s generators in radiopharmacies\n",
                $tc99m->symb,
            );
            calc_alignment_symb_len(
                $gp_dat3_new1,
                length $gp->file_header->info->[0],
                'centered',
            );
            $gp_dat3_new1 =
                $gp->cmt_symb.
                ($alignment->symb->bef x $alignment->symb->len).
                $gp_dat3_new1;
            print $gp_dat3_fh $gp_dat3_new1;
            $mo99_tc99m_actdyn_ws->write(
                $row++,
                $col,
                $gp_dat3_new1,
                $cell_form_dflt,
            );
        }

        else {
            say $gp_dat1_fh $gp->file_header->info->[$i];
            say $gp_dat2_fh $gp->file_header->info->[$i];
            say $gp_dat3_fh $gp->file_header->info->[$i];
            $mo99_tc99m_actdyn_ws->write(
                $row++,
                $col,
                $gp->file_header->info->[$i],
                $cell_form_dflt,
            );
        }

        # Blank lines
        if ($i =~ /\b[024]\b/ or $i == $k - 1) {
            say $gp_dat1_fh $gp->cmt_symb;
            say $gp_dat2_fh $gp->cmt_symb;
            say $gp_dat3_fh $gp->cmt_symb;
            $mo99_tc99m_actdyn_ws->write(
                $row++,
                $col,
                $gp->cmt_symb,
                $cell_form_dflt,
            );
        }
    }

    # Header
    $k = 0;
    @{$gp->file_header->header} = ();
    $gp->file_header->header->[$k++] = $gp->cmt_border->equals;
    $gp->file_header->header->[$k++] = "Calculation conditions";
    $gp->file_header->header->[$k]   = $gp->file_header->header->[0];
    for (my $i=0; $i<=$k; $i++) {
        if ($i !~ /\b[0]|$k\b/) {
            calc_alignment_symb_len(
                $gp->file_header->header->[$i],
                length $gp->file_header->header->[0],
                'centered',
            );

            $gp->file_header->header->[$i] =
                ($alignment->symb->bef x $alignment->symb->len).
                $gp->file_header->header->[$i];
            $gp->file_header->header->[$i] = sprintf(
                "%s %s",
                $gp->cmt_symb,
                $gp->file_header->header->[$i],
            );
        }
        say $gp_dat1_fh $gp->file_header->header->[$i];
        say $gp_dat2_fh $gp->file_header->header->[$i];
        say $gp_dat3_fh $gp->file_header->header->[$i];
        $mo99_tc99m_actdyn_ws->write(
            $row++,
            $col,
            $gp->file_header->header->[$i],
            $cell_form_dflt,
        );
    }

    # Subheader 1: Converter
    $k = 0;
    @{$gp->file_header->subheader} = ();
    $gp->file_header->subheader->[$k++] = $gp->cmt_border->dash;
    my $converter_name = $converter->name;
    $converter_name =~ s/^([\w]{1})/\u$1/;
    my $w_name = $w->name;
    $w_name =~ s/^([\w]{1})/\u$1/;
    $gp->file_header->subheader->[$k++] = sprintf(
        "%s: [%s]",
        $converter_name,
        $w_name,
    );
    $gp->file_header->subheader->[$k++] = $gp->file_header->subheader->[0];
    my $lt_col_width = "%23s";
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %s",
        "Shape",
        $geom->shape_opt->{$converter->geom->shape},
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g %s",
        "Radius",
        $converter->geom->rad1,
        $len->symb,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g %s",
        "hgt",
        $converter->geom->hgt,
        $len->symb,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g %s",
        "Volume",
        $converter->vol,
        $vol->symb,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g %s",
        "Mass density",
        $converter->mass_dens,
        $mass_dens->symb,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g %s",
        "Mass",
        $converter->mass,
        $mass->symb,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g %s",
        "Molar mass",
        $converter->molar_mass,
        $molar_mass->symb,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "%s Miscellaneous properties %s",
        '*' x 17,
        '*' x 17,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g %s",
        "Thermal conductivity",
        $converter->therm_cond,
        $therm_cond->symb,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g %s",
        "Melting point",
        $converter->melt_point,
        $temp->symb,
    );
    $gp->file_header->subheader->[$k] = sprintf(
        "$lt_col_width: %g %s",
        "Boiling point",
        $converter->boil_point,
        $temp->symb,
    );
    for (my $i=0; $i<=$#{$gp->file_header->subheader}; $i++) {
        if ($i == 1 or $i == 10) {
            calc_alignment_symb_len(
                $gp->file_header->subheader->[$i],
                length $gp->file_header->subheader->[0],
                'centered',
            );
            $gp->file_header->subheader->[$i] =
                ($alignment->symb->bef x $alignment->symb->len).
                $gp->file_header->subheader->[$i];
        }
        if ($i !~ /\b[02]\b/) {
            $gp->file_header->subheader->[$i] = sprintf(
                "%s %s",
                $gp->cmt_symb,
                $gp->file_header->subheader->[$i],
            );
        }
        say $gp_dat1_fh $gp->file_header->subheader->[$i];
        say $gp_dat2_fh $gp->file_header->subheader->[$i];
        say $gp_dat3_fh $gp->file_header->subheader->[$i];
        $mo99_tc99m_actdyn_ws->write(
            $row++,
            $col,
            $gp->file_header->subheader->[$i],
            $cell_form_dflt,
        );
        if ($i == 9) {
            say $gp_dat1_fh $gp->cmt_symb;
            say $gp_dat2_fh $gp->cmt_symb;
            say $gp_dat3_fh $gp->cmt_symb;
            $mo99_tc99m_actdyn_ws->write(
                $row++,
                $col,
                $gp->cmt_symb,
                $cell_form_dflt,
            );
        }
    }

    # Subheader 2: Mo target
    $k = 0;
    @{$gp->file_header->subheader} = ();
    $gp->file_header->subheader->[$k++] = $gp->cmt_border->dash;
    my $mo_tar_name = $mo_tar->name;
    $mo_tar_name =~ s/^([\w]{1})/\u$1/; # Cap the first letter
    $gp->file_header->subheader->[$k++] = sprintf(
        "%s: [%s]",
        $mo_tar_name,
        $mo_tar->symb,
    );
    $gp->file_header->subheader->[$k++] = $gp->file_header->subheader->[0];
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %s",
        "Shape",
        $geom->shape_opt->{$mo_tar->geom->shape},
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g %s",
        "Bottom radius",
        $mo_tar->geom->rad1,
        $len->symb,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g %s",
        "Top radius",
        $mo_tar->geom->rad2,
        $len->symb,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g %s",
        "Height",
        $mo_tar->geom->hgt,
        $len->symb,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g %s",
        "Volume",
        $mo_tar->vol,
        $vol->symb,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g %s",
        "Mass density",
        $mo_tar->mass_dens,
        $mass_dens->symb,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g %s",
        "Mass",
        $mo_tar->mass,
        $mass->symb,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g %s",
        "Molar mass",
        $mo_tar->molar_mass,
        $molar_mass->symb,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g",
        "Mo-100 mass fraction",
        $mo100->mass_frac,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "%s %s %s",
        '*' x 17,
        'Miscellaneous properties',
        '*' x 17,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g %s",
        "Thermal conductivity",
        $mo_tar->therm_cond,
        $therm_cond->symb,
    );
    $gp->file_header->subheader->[$k++] = sprintf(
        "$lt_col_width: %g %s",
        "Melting point",
        $mo_tar->melt_point,
        $temp->symb,
    );
    $gp->file_header->subheader->[$k] = sprintf(
        "$lt_col_width: %g %s",
        "Boiling point",
        $mo_tar->boil_point,
        $temp->symb,
    );
    for (my $i=0; $i<=$k; $i++) {
        if ($i == 1 or $i == 12) {
            calc_alignment_symb_len(
                $gp->file_header->subheader->[$i],
                length $gp->file_header->subheader->[0],
                'centered',
            );

            $gp->file_header->subheader->[$i] =
                ($alignment->symb->bef x $alignment->symb->len).
                $gp->file_header->subheader->[$i];
        }
        if ($i !~ /\b[02]\b/) {
            $gp->file_header->subheader->[$i] = sprintf(
                "%s %s",
                $gp->cmt_symb,
                $gp->file_header->subheader->[$i],
            );
        }
        say $gp_dat1_fh $gp->file_header->subheader->[$i];
        say $gp_dat2_fh $gp->file_header->subheader->[$i];
        say $gp_dat3_fh $gp->file_header->subheader->[$i];
        $mo99_tc99m_actdyn_ws->write(
            $row++,
            $col,
            $gp->file_header->subheader->[$i],
            $cell_form_dflt,
        );
        if ($i == 11) {
            say $gp_dat1_fh $gp->cmt_symb;
            say $gp_dat2_fh $gp->cmt_symb;
            say $gp_dat3_fh $gp->cmt_symb;
            $mo99_tc99m_actdyn_ws->write(
                $row++,
                $col,
                $gp->cmt_symb,
                $cell_form_dflt,
            );
        }
    }

    #
    # Date section
    #

    #
    # (i) Activity and specific activity of Mo-99
    #     as functions of electron beam energy
    #
    $gp->idx->block(0);
    foreach my $_nrg (@{$actdyn->nrgs_of_int}) {
        # Data block header
        # Col 1: Electron beam energy
        # Col 2: Irradiation time
        # Col 3: Mo-99 activity
        # Col 4: Mo mass
        # Col 5: Mo-99 specific activity

        $k = 0;
        @{$gp->col->header} = ();
        $gp->col->header->[$k++] = $gp->cmt_border->dash;
        $gp->col->header->[$k++] = sprintf(
            "gnuplot data block %d: Beam energy of %d %s",
            $gp->idx->block,
            $_nrg,
            $nrg->symb,
        );
        $gp->col->header->[$k++] = $gp->cmt_border->dash;
        $gp->col->header->[$k++] = sprintf(
            "x: Beam energy (%s)",
            $nrg->symb,
        );
        $gp->col->header->[$k++] = sprintf(
            "y: Irradiation time (%s)",
            $time->symb,
        );
        $gp->col->header->[$k++] = sprintf(
            "z: %s activity (%s per 1 %s)",
            $mo99->symb,
            $act->symb,
            $curr->symb,
        );
        $gp->col->header->[$k++] = sprintf(
            "%s mass (%s)",
            $mo->symb,
            $mass->symb,
        );
        $gp->col->header->[$k++] = sprintf(
            "%s specific activity (%s per 1 %s)",
            $mo99->symb,
            $sp_act->symb,
            $curr->symb,
        );
        $gp->col->header->[$k] = $gp->col->header->[0];

        lengthen_cmt_border(
            $gp,
            [0, 1, 2, $k],
            [0, 2, $k],
            $gp->cmt_symb,
            $symb->dash,
        );

        for (my $i=0; $i<=$k; $i++) {
            if ($i == 1) {
                calc_alignment_symb_len(
                    $gp->col->header->[$i],
                    length $gp->col->header->[0],
                    'centered',
                );
                $gp->col->header->[$i] =
                    ($alignment->symb->bef x $alignment->symb->len).
                    $gp->col->header->[$i];
            }
            if ($i == 1) {
                $gp->col->header->[$i] =
                    $gp->cmt_symb.$gp->col->header->[$i];
            }
            if ($i == 3) {
                $gp->col->header->[$i] =
                    $gp->cmt_symb." ".$gp->col->header->[$i];
            }
            if ($i =~ /\b[3-6]\b/) {
                # If the comma or tab is used as the data separator,
                # use that separator as the block head separator, too.
                # Otherwise, use the predefined header separator.
                $gp->col->header->[$i] .=
                    $gp->col->content_sep eq $symb->comma ?
                        $gp->col->content_sep :
                    $gp->col->content_sep eq $symb->tab ?
                        $gp->col->content_sep :
                        $gp->col->header_sep;
            }
            print $gp_dat1_fh $gp->col->header->[$i];
            print $gp_dat1_fh "\n" if ($i =~ /\b[0-2]|$k\b/ or $i == $k - 1);
        }

        # Data columns
        # Col 1: Electron beam energy
        # Col 2: Irradiation time
        # Col 3: Mo-99 activity
        # Col 4: Mo mass
        # Col 5: Mo-99 specific activity
        foreach my $t ($t_tot->from..$t_tot->to) {
            $k = 0;
            @{$gp->col->content} = ();
            $gp->col->content->[$k++] = sprintf("%g", $_nrg);
            $gp->col->content->[$k++] = sprintf("%g", $t);
            $gp->col->content->[$k++] = sprintf(
                "%g",
                $mo99->act->irr_arr->[$_nrg][$t],
            );
            $gp->col->content->[$k++] = sprintf(
                "%g",
                $mo->mass,
            );
            $gp->col->content->[$k] = sprintf(
                "%g",
                $mo99->sp_act->irr_arr->[$_nrg][$t],
            );
            # > Relate the indices of 'col->content' and 'col->header'
            #   to calculate the number of spaces to be appended to
            #   'col->content' wrto the width of 'col->header', which
            #   will lead to the ragged-right alignment of 'col->content'.
            # > 0 => '3' means that the 3rd index of @{$gp->col->header}
            #   is the header of the 0th index of @{$gp->col->content}.
            %{$gp->col->content_to_header} = ();
            %{$gp->col->content_to_header} = (
                # (key) Index of @{$gp->col->content}
                # (val) Index of @{$gp->col->header}
                0 => '3',
                1 => '4',
                2 => '5',
                3 => '6',
                # Exclude the last item.
            );

            # Append column data separators.
            # Skip the last element of @{$gp->col->content}, however,
            # "not to" (by the -1 of '$#{$gp->col->content} - 1' in
            # the loop conditional) feed appending spaces to the last column.

            # Case 1
            # > Space as the data sep
            # > Append calculated numbers of spaces for ragged-right alignment.
            if ($gp->col->content_sep eq $symb->space) {
                for (my $i=0; $i<=($k - 1); $i++) {
                    calc_alignment_symb_len(
                        $gp->col->content->[$i],
                        length(
                            ${$gp->col->header}
                                [$gp->col->content_to_header->{$i}]
                        ),
                        'ragged',
                    );
                    $gp->col->content->[$i] .=
                        ($gp->col->content_sep x $alignment->symb->len);
                }
            }

            # Case 2
            # > Comma or tab as the data sep
            # > Append only one separator
            elsif (
                $gp->col->content_sep eq $symb->comma
                or $gp->col->content_sep eq $symb->tab
            ) {
                for (my $i=0; $i<=($#{$gp->col->content} - 1); $i++) {
                    $gp->col->content->[$i] .= $gp->col->content_sep;
                }
            }

            # Write the aligned columnar data (one row at a time).
            for (my $i=0; $i<=$k; $i++) {
                print $gp_dat1_fh $gp->col->content->[$i];
            }
            print $gp_dat1_fh "\n";
        }

        # Move on to the next gnuplot data index.
        $gp->idx->block($gp->idx->block + 1);

        # Feed one blank line indicating the end of a gnuplot data block,
        # and mark the end of the gnuplot data file.
        print $gp_dat1_fh $_nrg != $actdyn->nrgs_of_int->[-1] ?
                $gp->end_of->block : $gp->end_of->file;
    }
    close $gp_dat1_fh;

    #
    # (ii) Activity and specific activity of Mo-99
    #      as functions of electron beam energy and irradiation time
    #

    $gp->idx->dataset(0);
    foreach my $teoi (@{$mo99_act_nrg->tirrs_of_int}) {
        # Data block header
        # Col 1: Electron beam energy
        # Col 2: Mo-99 activity
        # Col 3: Mo mass
        # Col 4: Mo-99 specific activity
        $k = 0;
        @{$gp->col->header} = ();
        $gp->col->header->[$k++] = $gp->cmt_border->dash;
        $gp->col->header->[$k++] = sprintf(
            "gnuplot dataset index [%d]: At irradiation time [%g %s]",
            $gp->idx->dataset,
            $teoi,
            $time->symb,
        );
        $gp->col->header->[$k++] = $gp->cmt_border->dash;
        $gp->col->header->[$k++] = sprintf(
            "x: Beam energy (%s)",
            $nrg->symb,
        );
        $gp->col->header->[$k++] = sprintf(
            "y: %s activity (%s per 1 %s)",
            $mo99->symb,
            $act->symb,
            $curr->symb,
        );
        $gp->col->header->[$k++] = sprintf(
            "%s mass (%s)",
            $mo->symb,
            $mass->symb,
        );
        $gp->col->header->[$k++] = sprintf(
            "%s specific activity (%s per 1 %s)",
            $mo99->symb,
            $sp_act->symb,
            $curr->symb,
        );
        $gp->col->header->[$k] = $gp->col->header->[0];
        lengthen_cmt_border(
            $gp,
            [0, 1, 2, $k],
            [0, 2, $k],
            $gp->cmt_symb,
            $symb->dash,
        );

        for (my $i=0; $i<=$k; $i++) {
            if ($i == 1) {
                calc_alignment_symb_len(
                    $gp->col->header->[$i],
                    length $gp->col->header->[0],
                    'centered',
                );
                $gp->col->header->[$i] =
                    ($alignment->symb->bef x $alignment->symb->len).
                    $gp->col->header->[$i];
            }
            if ($i == 1) {
                $gp->col->header->[$i] =
                    $gp->cmt_symb.$gp->col->header->[$i];
            }
            if ($i == 3) {
                $gp->col->header->[$i] =
                    $gp->cmt_symb." ".$gp->col->header->[$i];
            }
            if ($i =~ /\b[345]\b/) {
                $gp->col->header->[$i] .=
                    $gp->col->content_sep eq $symb->comma ?
                        $gp->col->content_sep :
                    $gp->col->content_sep eq $symb->tab ?
                        $gp->col->content_sep :
                        $gp->col->header_sep;
            }

            print $gp_dat2_fh $gp->col->header->[$i];
            print $gp_dat2_fh "\n" if ($i =~ /\b[0-2]|$k\b/ or $i == $k -1);
        }

        # Data columns
        # Col 1: Electron beam energy
        # Col 2: Mo-99 activity
        # Col 3: Mo mass
        # Col 4: Mo-99 specific activity
        @{$gp->col->content} = ();
        foreach my $_nrg (@{$actdyn->nrgs_of_int}) {
            $k = 0;
            $gp->col->content->[$k++] = sprintf("%g", $_nrg);
            $gp->col->content->[$k++] = sprintf(
                "%g",
                $mo99->act->irr_arr->[$_nrg][$teoi],
            );
            $gp->col->content->[$k++] = sprintf(
                "%g",
                $mo->mass,
            );
            $gp->col->content->[$k] = sprintf(
                "%g",
                $mo99->sp_act->irr_arr->[$_nrg][$teoi],
            );
            %{$gp->col->content_to_header} = ();
            %{$gp->col->content_to_header} = (
                0 => '3',
                1 => '4',
                2 => '5',
            );

            if ($gp->col->content_sep eq $symb->space) {
                for (my $i=0; $i<=($k - 1); $i++) {
                    calc_alignment_symb_len(
                        $gp->col->content->[$i],
                        length(
                            ${$gp->col->header}
                            [$gp->col->content_to_header->{$i}]
                        ),
                        'ragged',
                    );
                    $gp->col->content->[$i] .=
                        ($gp->col->content_sep x $alignment->symb->len);
                }
            }

            elsif (
                $gp->col->content_sep eq $symb->comma
                or $gp->col->content_sep eq $symb->tab
            ) {
                for (my $i=0; $i<=($k - 1); $i++) {
                    $gp->col->content->[$i] .= $gp->col->content_sep;
                }
            }

            for (my $i=0; $i<=$k; $i++) {
                print $gp_dat2_fh $gp->col->content->[$i];
            }
            print $gp_dat2_fh "\n";
        }

        $gp->idx->dataset($gp->idx->dataset + 1);

        print $gp_dat2_fh $teoi != $mo99_act_nrg->tirrs_of_int->[-1] ?
            $gp->end_of->dataset : $gp->end_of->file;
    }
    close $gp_dat2_fh;

    #
    # (iii) Mo-99 and Tc-99m activity dynamics
    #

    # Data block header
    # Col 1:  Data row index
    # Col 2:  Time elapsed
    # Col 3:  Mo-99 activity
    # Col 4:  Mo mass
    # Col 5:  Mo-99 specific activity
    # Col 6:  Mo-99 saturation activity
    # Col 7:  Mo-99 specific saturation activity
    # Col 8:  Ratio of Mo-99 activity to Mo-99 saturation activity
    # Col 9:  Mo-99 decay activity
    # Col 10: Mo-99 specific decay activity
    # Col 11: Tc-99m irradiation activity
    # Col 12: Tc-99m decay activity
    # Col 13: Tc-99m elution activity
    # Col 14: Time frame marks
    $k = 0;
    @{$gp->col->header} = ();
    $gp->col->header->[$k++] = $gp->cmt_border->dash;
    $gp->col->header->[$k++] = sprintf(
        "gnuplot data: [%s/%s] activities".
        " at beam energy of [%g %s] and [%g %s]",
        $mo99->symb,
        $tc99m->symb,
        $linac->op_nrg,
        $nrg->symb,
        $linac->op_avg_beam_curr,
        $curr->symb,
    );
    $gp->col->header->[$k++] = $gp->cmt_border->dash;
    $gp->col->header->[$k++] = "Data row index"; # 1st data column
    $gp->col->header->[$k++] = sprintf(
        "Time elapsed (%s)",
        $time->symb,
    );
    $gp->col->header->[$k++] = sprintf(
        "%s activity (%s)",
        $mo99->symb,
        $act->symb,
    );
    $gp->col->header->[$k++] = sprintf(
        "%s mass (%s)",
        $mo->symb,
        $mass->symb,
    );
    $gp->col->header->[$k++] = sprintf(
        "%s specific activity (%s)",
        $mo99->symb,
        $sp_act->symb,
    );
    $gp->col->header->[$k++] = sprintf(
        "%s saturation activity (%s)",
        $mo99->symb,
        $act->symb,
    );
    $gp->col->header->[$k++] = sprintf(
        "%s specific saturation activity (%s)",
        $mo99->symb,
        $sp_act->symb,
    );
    $gp->col->header->[$k++] = sprintf(
        "Ratio of %s activity to its saturation value",
        $mo99->symb,
    );
    $gp->col->header->[$k++] = sprintf(
        "%s decay activity (%s)",
        $mo99->symb,
        $act->symb,
    );
    $gp->col->header->[$k++] = sprintf(
        "%s specific decay activity (%s)",
        $mo99->symb,
        $sp_act->symb,
    );
    $gp->col->header->[$k++] = sprintf(
        "%s irradiation activity (%s)",
        $tc99m->symb,
        $act->symb,
    );
    $gp->col->header->[$k++] = sprintf(
        "%s decay activity (%s)",
        $tc99m->symb,
        $act->symb,
    );
    $gp->col->header->[$k++] = sprintf(
        "%s eluate activity (%s)",
        $tc99m->symb,
        $act->symb,
    );
    $gp->col->header->[$k++] = "Time frame mark";
    $gp->col->header->[$k] = $gp->col->header->[0];
    lengthen_cmt_border(
        $gp,
        [0, 1, 2, $k],
        [0, 2, $k],
        $gp->cmt_symb,
        $symb->dash,
    );

    for (my $i=0; $i<=$k; $i++) {
        if ($i == 1) {
            calc_alignment_symb_len(
                $gp->col->header->[$i],
                length $gp->col->header->[0],
                'centered',
            );
            $gp->col->header->[$i] =
                ($alignment->symb->bef x $alignment->symb->len).
                $gp->col->header->[$i];
        }
        if ($i == 1) {
            $gp->col->header->[$i] =
                $gp->cmt_symb.$gp->col->header->[$i];
        }
        if ($i == 3) {
            $gp->col->header->[$i] =
                $gp->cmt_symb." ".$gp->col->header->[$i];
        }
        if ($i =~ /\b[3-9]\b/ or ($i >= 10 and $i <= 15)) {
            $gp->col->header->[$i] .=
                $gp->col->content_sep eq $symb->comma ?
                    $gp->col->content_sep :
                $gp->col->content_sep eq $symb->tab ?
                    $gp->col->content_sep :
                    $gp->col->header_sep;
        }

        print $gp_dat3_fh $gp->col->header->[$i];
        print $gp_dat3_fh "\n" if ($i =~ /\b(?:[0-2]|$k)\b/ or $i == ($k - 1));

        # v Spreadsheet-only
        # Delimiter lines
        if ($i =~ /\b[0-2]\b/ or $i == $k) {
            $mo99_tc99m_actdyn_ws->write(
                $row++,
                $col,
                sprintf("%s\n", $gp->col->header->[$i]),
                $cell_form_dflt,
            );
        }
        # Header
        else {
            $mo99_tc99m_actdyn_ws->write(
                $i == ($k - 1) ?
                    ($row++, $col, $gp->col->header->[$i], $cell_form_head) :
                    ($row, $col++, $gp->col->header->[$i], $cell_form_head)
            );
            $col = 0 if $i == $k - 1; # Initialize col num
        }
    }

    # Data columns
    # Col 1:  Data row index
    # Col 2:  Time elapsed
    # Col 3:  Mo-99 activity
    # Col 4:  Mo mass
    # Col 5:  Mo-99 specific activity
    # Col 6:  Mo-99 saturation activity
    # Col 7:  Mo-99 specific saturation activity
    # Col 8:  Ratio of Mo-99 activity to Mo-99 saturation activity
    # Col 9:  Mo-99 decay activity
    # Col 10: Mo-99 specific decay activity
    # Col 11: Tc-99m irradiation activity
    # Col 12: Tc-99m decay activity
    # Col 13: Tc-99m elution activity
    # Col 14: Time frame marks
    @{$gp->col->content} = ();
    $gp->idx->row(0);
    my $elu_count = 1;
    foreach my $t ($t_tot->from..$t_tot->to) {
        # At EOP: An additional data row for Mo-99/Tc-99m decay activities
        if ($t == $t_pro->to) {
            $col = 0; # Worksheet
            $k = 0;
            $gp->col->content->[$k++] = sprintf(
                "[%d]",
                $gp->idx->row,
            );
            # The divisor '$time->factor' is important
            # for reflecting the unit conversion!
            $gp->col->content->[$k++] = sprintf("%g", $t);
            $gp->col->content->[$k++] = sprintf(
                "%g",
                $mo99->act->irr_arr->[$linac->op_nrg][$t],
            );
            $gp->col->content->[$k++] = sprintf(
                "%g",
                $mo->mass,
            );
            $gp->col->content->[$k++] = sprintf(
                "%g",
                $mo99->sp_act->irr_arr->[$linac->op_nrg][$t],
            );
            $gp->col->content->[$k++] = sprintf(
                "%g",
                $mo99->act->sat_arr->[$linac->op_nrg][$t],
            );
            $gp->col->content->[$k++] = sprintf(
                "%g",
                $mo99->sp_act->sat_arr->[$linac->op_nrg][$t],
            );
            $gp->col->content->[$k++] = sprintf(
                "%g",
                $mo99->act->ratio_irr_to_sat_arr->[$linac->op_nrg][$t],
            );
            $gp->col->content->[$k++] = sprintf(
                "%g",
                (
                    $mo99->act->dec_arr->[$linac->op_nrg][$t]
                    / (1 - $chem_proc->mo99_loss_ratio_at_eop)
                ),
            );
            $gp->col->content->[$k++] = sprintf(
                "%g",
                (
                    $mo99->sp_act->dec_arr->[$linac->op_nrg][$t]
                    / (1 - $chem_proc->mo99_loss_ratio_at_eop)
                ),
            );
            $gp->col->content->[$k++] = sprintf(
                "%g",
                $tc99m->act->irr_arr->[$linac->op_nrg][$t],
            );
            $gp->col->content->[$k++] = sprintf(
                "%g",
                (
                    $tc99m->act->dec_arr->[$linac->op_nrg][$t]
                    / (1 - $chem_proc->tc99m_loss_ratio_at_eop)
                ),
            );
            $gp->col->content->[$k++] = sprintf(
                "%g",
                (
                    $tc99m->act->elu_arr->[$linac->op_nrg][$t]
                    / (1 - $chem_proc->tc99m_loss_ratio_at_eop)
                ),
            );
            $gp->col->content->[$k] = sprintf(
                "%s",
                $mark_time_frame_of->eop,
            );

            # Apply the operating average beam current of the linac.
            for (my $i=2; $i<=$k; $i++) {
                unless ($i == 3 or $i == 7 or $i == 13) {
                    $gp->col->content->[$i] *= $linac->op_avg_beam_curr;
                }
            }

            %{$gp->col->content_to_header} = ();
            %{$gp->col->content_to_header} = (
                0  => '3',
                1  => '4',
                2  => '5',
                3  => '6',
                4  => '7',
                5  => '8',
                6  => '9',
                7  => '10',
                8  => '11',
                9  => '12',
                10 => '13',
                11 => '14',
                12 => '15',
            );
            if ($gp->col->content_sep eq $symb->space) {
                for (my $i=0; $i<=($k - 1); $i++) {
                    calc_alignment_symb_len(
                        $gp->col->content->[$i],
                        length(
                            ${$gp->col->header}
                            [$gp->col->content_to_header->{$i}]
                        ),
                        'ragged',
                    );
                    $gp->col->content->[$i] .=
                        ($gp->col->content_sep x $alignment->symb->len);
                }
            }
            elsif (
                   $gp->col->content_sep eq $symb->comma
                or $gp->col->content_sep eq $symb->tab
            ) {
                for (my $i=0; $i<=($k - 1); $i++) {
                    $gp->col->content->[$i] .= $gp->col->content_sep;
                }
            }
            for (my $i=0; $i<=$k; $i++) {
                print $gp_dat3_fh $gp->col->content->[$i];
                $mo99_tc99m_actdyn_ws->write( $i == $#{$gp->col->content} ?
                    ($row, $col++, $gp->col->content->[$i], $cell_form_emph) :
                    ($row, $col++, $gp->col->content->[$i], $cell_form_dflt)
                );
            }
            $row++; # Spreadsheet
            print $gp_dat3_fh "\n";

            # Move on to the next data row (not an "index")
            $gp->idx->row($gp->idx->row + 1);
        }

        # At Tc-99m elutions: Additional data rows for Tc-99m elution activities
        if (
            # e.g. $t >= 96
            $t >= $t_del->to
            # e.g. $t == 96, 120, 144, ..., 336
            and ($t - $t_del->to) % $tc99m_gen->elu_itv == 0
            # e.g. $t <= 336 ($t <= 96 + 240)
            and $t <= ($t_del->to + $tc99m_gen->shelf_life)
        ) {
            $col = 0;
            $gp->col->content->[0] = sprintf(
                "[%d]",
                $gp->idx->row,
            );
            $gp->col->content->[1] = sprintf(
                "%g",
                $t,
            );
            $gp->col->content->[2] = sprintf(
                "%g",
                $mo99->act->irr_arr->[$linac->op_nrg][$t],
            );
            $gp->col->content->[3] = sprintf(
                "%g",
                $mo->mass,
            );
            $gp->col->content->[4] = sprintf(
                "%g",
                $mo99->sp_act->irr_arr->[$linac->op_nrg][$t],
            );
            $gp->col->content->[5] = sprintf(
                "%g",
                $mo99->act->sat_arr->[$linac->op_nrg][$t],
            );
            $gp->col->content->[6] = sprintf(
                "%g",
                $mo99->sp_act->sat_arr->[$linac->op_nrg][$t],
            );
            $gp->col->content->[7] = sprintf(
                "%g",
                $mo99->act->ratio_irr_to_sat_arr->[$linac->op_nrg][$t],
            );
            $gp->col->content->[8] = sprintf(
                "%g",
                $mo99->act->dec_arr->[$linac->op_nrg][$t],
            );
            $gp->col->content->[9] = sprintf(
                "%g",
                $mo99->sp_act->dec_arr->[$linac->op_nrg][$t],
            );
            $gp->col->content->[10] = sprintf(
                "%g",
                $tc99m->act->irr_arr->[$linac->op_nrg][$t],
            );
            $gp->col->content->[11] = sprintf(
                "%g", # Recover the bef-lost one.
                (
                    $tc99m->act->dec_arr->[$linac->op_nrg][$t]
                    / (1 - $tc99m_gen->elu_eff)
                ),
            );
            $gp->col->content->[12] = sprintf(
                "%g",
                $tc99m->act->elu_arr->[$linac->op_nrg][$t],
            );
            $gp->col->content->[13] = sprintf(
                "%s No. %d",
                $mark_time_frame_of->elu,
                $elu_count,
            );
            # Conditional appending for the EOD
            if ($t == $t_del->to) {
                $gp->col->content->[13] .= sprintf(
                    " (%s)",
                    $mark_time_frame_of->eod,
                );
            }
            for (my $i=2; $i<=$#{$gp->col->content}; $i++) {
                unless ($i == 3 or $i == 7 or $i == 13) {
                    $gp->col->content->[$i] *= $linac->op_avg_beam_curr;
                }
            }
            %{$gp->col->content_to_header} = ();
            %{$gp->col->content_to_header} = (
                0  => '3',
                1  => '4',
                2  => '5',
                3  => '6',
                4  => '7',
                5  => '8',
                6  => '9',
                7  => '10',
                8  => '11',
                9  => '12',
                10 => '13',
                11 => '14',
                12 => '15',
            );
            if ($gp->col->content_sep eq $symb->space) {
                for (my $i=0; $i<=($#{$gp->col->content} - 1); $i++) {
                    calc_alignment_symb_len(
                        $gp->col->content->[$i],
                        length(
                            ${$gp->col->header}
                            [$gp->col->content_to_header->{$i}]
                        ),
                        'ragged',
                    );
                    $gp->col->content->[$i] .=
                        ($gp->col->content_sep x $alignment->symb->len);
                }
            }
            elsif (
                   $gp->col->content_sep eq $symb->comma
                or $gp->col->content_sep eq $symb->tab
            ) {
                for (my $i=0; $i<=($#{$gp->col->content} - 1); $i++) {
                    $gp->col->content->[$i] .= $gp->col->content_sep;
                }
            }
            for (my $i=0; $i<=$#{$gp->col->content}; $i++) {
                print $gp_dat3_fh $gp->col->content->[$i];
                $mo99_tc99m_actdyn_ws->write( $i == $#{$gp->col->content} ?
                    ($row, $col++, $gp->col->content->[$i], $cell_form_emph) :
                    ($row, $col++, $gp->col->content->[$i], $cell_form_dflt)
                );
            }
            $row++; # Spreadsheet
            print $gp_dat3_fh "\n";

            # Move on to the next data row (not an "index")
            $gp->idx->row($gp->idx->row + 1);

            # Increment the elution count for writing
            $elu_count++;
        }

        #
        # Those "except" at the EOP
        #
        $col = 0;
        $gp->col->content->[0] = sprintf(
            "[%d]",
            $gp->idx->row,
        );
        $gp->col->content->[1] = sprintf(
            "%g",
            $t,
        );
        $gp->col->content->[2] = sprintf(
            "%g",
            $mo99->act->irr_arr->[$linac->op_nrg][$t],
        );
        $gp->col->content->[3] = sprintf(
            "%g",
            $mo->mass,
        );
        $gp->col->content->[4] = sprintf(
            "%g",
            $mo99->sp_act->irr_arr->[$linac->op_nrg][$t],
        );
        $gp->col->content->[5] = sprintf(
            "%g",
            $mo99->act->sat_arr->[$linac->op_nrg][$t],
        );
        $gp->col->content->[6] = sprintf(
            "%g",
            $mo99->sp_act->sat_arr->[$linac->op_nrg][$t],
        );
        $gp->col->content->[7] = sprintf(
            "%g",
            $mo99->act->ratio_irr_to_sat_arr->[$linac->op_nrg][$t],
        );
        $gp->col->content->[8] = sprintf(
            "%g",
            $mo99->act->dec_arr->[$linac->op_nrg][$t],
        );
        $gp->col->content->[9] = sprintf(
            "%g",
            $mo99->sp_act->dec_arr->[$linac->op_nrg][$t],
        );
        $gp->col->content->[10] = sprintf(
            "%g",
            $tc99m->act->irr_arr->[$linac->op_nrg][$t],
        );
        $gp->col->content->[11] = sprintf(
            "%g",
            $tc99m->act->dec_arr->[$linac->op_nrg][$t],
        );
        $gp->col->content->[12] = sprintf(
            "%g",
            $tc99m->act->elu_arr->[$linac->op_nrg][$t],
        );
        $gp->col->content->[13] = sprintf(
            "%s",
            $mark_time_frame_of->non,
        );
        # Conditional overwriting for the EOI mark
        if ($t == $t_irr->to) {
            $gp->col->content->[13] = sprintf(
                "%s",
                $mark_time_frame_of->eoi,
            );
        }
        for (my $i=2; $i<=$#{$gp->col->content}; $i++) {
            unless ($i == 3 or $i == 7 or $i == 13) {
                $gp->col->content->[$i] *= $linac->op_avg_beam_curr;
            }
        }
        %{$gp->col->content_to_header} = ();
        %{$gp->col->content_to_header} = (
            0  => '3',
            1  => '4',
            2  => '5',
            3  => '6',
            4  => '7',
            5  => '8',
            6  => '9',
            7  => '10',
            8  => '11',
            9  => '12',
            10 => '13',
            11 => '14',
            12 => '15',
        );
        if ($gp->col->content_sep eq $symb->space) {
            for (my $i=0; $i<=($#{$gp->col->content} - 1); $i++) {
                calc_alignment_symb_len(
                    $gp->col->content->[$i],
                    length(
                        ${$gp->col->header}
                        [$gp->col->content_to_header->{$i}]
                    ),
                    'ragged',
                );
                $gp->col->content->[$i] .=
                    ($gp->col->content_sep x $alignment->symb->len);
            }
        }
        elsif (
               $gp->col->content_sep eq $symb->comma
            or $gp->col->content_sep eq $symb->tab
        ) {
            for (my $i=0; $i<=($#{$gp->col->content} - 1); $i++) {
                $gp->col->content->[$i] .= $gp->col->content_sep;
            }
        }
        for (my $i=0; $i<=$#{$gp->col->content}; $i++) {
            print $gp_dat3_fh $gp->col->content->[$i];
            $mo99_tc99m_actdyn_ws->write(
                (
                    $i == $#{$gp->col->content} and
                    $gp->col->content->[$#{$gp->col->content}] =~ /[\w]+/
                ) ? ($row, $col++, $gp->col->content->[$i], $cell_form_emph) :
                    ($row, $col++, $gp->col->content->[$i], $cell_form_dflt)
            );
        }
        $row++; # Spreadsheet
        print $gp_dat3_fh "\n";

        # Move on to the next data row (not an "index")
        $gp->idx->row($gp->idx->row + 1);

        #
        # Total activity of Tc-99m eluates
        #
        $col = 0;

        # Calculate the indentation width and construct a conversion
        # wrto that indentation
        my($len, $len_conv);

        if ($gp->col->content_sep eq $symb->space) {
            $len =
                $gp->col->header_border_len
                - length($gp->col->header->[15]) # Tc-99m eluate act column
                - length($gp->col->header->[16]) # The last column
                - 2; # Manually adjust it.
            $len_conv = '%'.$len.'s';
        }
        elsif (
               $gp->col->content_sep eq $symb->comma
            or $gp->col->content_sep eq $symb->tab
        ) {
            # -1 excludes time frame mark col
            $len = ($#{$gp->col->content} - 1);
            $len_conv = '%s'.($gp->col->content_sep x $len); # Not *, but x
        }
        my $lab = sprintf(
            "Sum of %d-time %s elutions (the first %s eluate",
            $tc99m_gen->tot_num_of_elu,
            $tc99m->symb,
            $tc99m->symb
        );
        # Append an explanation if or not the first Tc-99m
        # eluate has been excluded form the total activity
        # of the Tc-99m eluates.
        $lab .= $tc99m_gen->elu_ord_from == 1 ?
            ' included): ' : ' excluded): ';

        # Write the total activity of Tc-99m eluates with the label
        if ($t == $t_tot->to) {
            printf $gp_dat3_fh
                "%s$len_conv%g\n",
                $gp->cmt_symb,
                $lab,
                (
                    $tc99m->act->elu_tot_arr->[$linac->op_nrg]
                    * $linac->op_avg_beam_curr
                );
            $mo99_tc99m_actdyn_ws->write(
                $row++,
                $col,
                sprintf(
                    "%s%s%g\n",
                    $gp->cmt_symb,
                    $lab,
                    (
                        $tc99m->act->elu_tot_arr->[$linac->op_nrg]
                        * $linac->op_avg_beam_curr
                    ),
                ),
                $cell_form_dflt
            );
        }

        # Mark the end of the gnuplot input data file.
        if ($t == $t_tot->to) {
            print $gp_dat3_fh $gp->end_of->file ;
            $mo99_tc99m_actdyn_ws->write(
                $row++, $col, $gp->end_of->file, $cell_form_dflt
            );
        }
    }
    close $gp_dat3_fh;
    $mo99_tc99m_actdyn_wb->close();

    # Notification - ending
    say $disp->border->dash;
    pause_terminal() if $routine->is_verbose;
    notify_file_gen(
        $mo99_act_nrg_tirr->gp->dat,
        $mo99_act_nrg->gp->dat,
        $mo99_tc99m_actdyn->gp->dat,
        $mo99_tc99m_actdyn->excel->xlsx,
    );

    return;
}


sub calc_num_of_required_linacs {
    # """Calculate the number of linacs necessary to meet the Tc-99m demand
    # of the countries of interest."""

    # Two 72-hour long production runs can be performed per week
    $linac->tc99m_supply->weekly(
        $tc99m->act->elu_tot_arr->[$linac->op_nrg]
        * $linac->op_avg_beam_curr
        * 2
    );

    foreach my $k (sort keys %{$country->list}) {
        # Redirection
        my $nation = $country->list->{$k}{obj};
        next if not $nation->tc99m_demand_num->weekly;

        # Tc-99m demand per week
        $nation->tc99m_demand_act->weekly(
            $nation->tc99m_demand_num->weekly
            * $tc99m->avg_dose
        );

        # Tc-99m supply per week
        $nation->req_num_linacs(
            $nation->tc99m_demand_act->weekly
            / $linac->tc99m_supply->weekly
        );

        # Reporting
        my $rpt_fname = sprintf(
            "%s%s.dat",
            $actdyn->path,
            $k,
        );
        open my $rpt_fh, '>:encoding(UTF-8)', $rpt_fname;
        my %fh_tee = (
            rpt => $rpt_fh,
            scr => *STDOUT,
        );
        foreach my $fh (sort values %fh_tee) {
            say $fh $disp->border->dash;
            printf $fh (
                "%sCountry: [%s]\n",
                $disp->indent,
                $nation->name,
            );
            printf $fh (
                "%s%s demand per week: [%s %s]\n",
                $disp->indent,
                $tc99m->symb,
                commify(sprintf("%.2f", $nation->tc99m_demand_act->weekly)),
                $act->symb,
            );
            printf $fh (
                "%s%s supply per linac per week: [%s %s]\n",
                $disp->indent,
                $tc99m->symb,
                commify(sprintf("%.2f", $linac->tc99m_supply->weekly)),
                $act->symb,
            );
            printf $fh (
                "%sThe number of linacs meeting %s demand: [%.2f] or [%d]\n",
                $disp->indent,
                $tc99m->symb,
                $nation->req_num_linacs,
                ceil($nation->req_num_linacs),
            );
            say $fh $disp->border->dash;
        }
        close $rpt_fh;
        notify_file_gen($rpt_fname);
    };

    return;
}


sub populate_attrs {
    # """Populate object attributes."""

    #
    # 'symbol' object
    #
    $symb->tilde('~');
    $symb->backtick('`');
    $symb->exclamation('!');
    $symb->at_sign('@');
    $symb->hash('#');
    $symb->dollor('$');
    $symb->percent('%');
    $symb->caret('^');
    $symb->ampersand('&');
    $symb->asterisk('*');
    $symb->paren_lt('(');
    $symb->paren_rt(')');
    $symb->dash('-');
    $symb->underscore('_');
    $symb->plus('+');
    $symb->equals('=');
    $symb->bracket_lt('[');
    $symb->bracket_rt(']');
    $symb->curl_lt('{');
    $symb->curl_rt('}');
    $symb->backslash('/');
    $symb->vert_bar('|');
    $symb->semicolon(';');
    $symb->colon(':');
    $symb->quote('\'');
    $symb->double_quote('"');
    $symb->comma(',');
    $symb->angle_quote_lt('<');
    $symb->period('.');
    $symb->angle_quote_rt('>');
    $symb->slash('/');
    $symb->question('?');
    $symb->space(' ');
    $symb->tab("\t"); # Use double quotes to use \t

    #
    # 'display' object
    #
    $disp->clear("\n" x 3);
    $disp->indent(" ");
    $disp->border->len(70);
    $disp->border->asterisk($symb->asterisk x $disp->border->len);
    $disp->border->dash($symb->dash x $disp->border->len);
    $disp->border->plus($symb->plus x $disp->border->len);
    $disp->border->equals($symb->equals x $disp->border->len);
    $disp->border->warning($disp->border->plus);

    #
    # 'alignment' object
    #
    $alignment->symb->bef($symb->space);
    $alignment->symb->aft($symb->space);

    #
    # 'default' object
    #
    $dflt->mark('present');

    #
    # 'metric_pref' objects
    #
    $exa->symbol('E');
    $exa->factor(1e+18);
    $peta->symbol('P');
    $peta->factor(1e+15);
    $tera->symbol('T');
    $tera->factor(1e+12);
    $giga->symbol('G');
    $giga->factor(1e+9);
    $mega->symbol('M');
    $mega->factor(1e+6);
    $kilo->symbol('k');
    $kilo->factor(1e+3);
    $hecto->symbol('h');
    $hecto->factor(1e+2);
    $deca->symbol('da');
    $deca->factor(1e+1);
    $no_metric_pref->symbol('');
    $no_metric_pref->factor(1);
    $deci->symbol('d');
    $deci->factor(1e-1);
    $centi->symbol('c');
    $centi->factor(1e-2);
    $milli->symbol('m');
    $milli->factor(1e-3);
    $micro->symbol('u');
    $micro->factor(1e-6);
    $nano->symbol('n');
    $nano->factor(1e-9);
    $pico->symbol('p');
    $pico->factor(1e-12);
    $femto->symbol('f');
    $femto->factor(1e-15);
    $atto->symbol('a');
    $atto->factor(1e-18);
    $kelv->factor(0);
    $kelv_to_cels->factor(-273.15);
    $bq_per_ci->symbol(''); # Used for conversion between Bq and Ci
    $bq_per_ci->factor(3.7e+10);
    $hr_per_sec->factor(1/3600);
    $hr_per_min->factor(1/60);
    $hr_per_day->factor(24);
    %{$metric_pref->list} = (
        # (key) Power of 10
        # (val) 'metric_pref' object
        18  => $exa,
        15  => $peta,
        12  => $tera,
        9   => $giga,
        6   => $mega,
        3   => $kilo,
        2   => $hecto,
        1   => $deca,
        0   => $no_metric_pref,
        -1  => $deci,
        -2  => $centi,
        -3  => $milli,
        -6  => $micro,
        -9  => $nano,
        -12 => $pico,
        -15 => $femto,
        -18 => $atto,
        # Special key-val pairs
        'kelv'         => $kelv,
        'kelv_to_cels' => $kelv_to_cels,
        'bq_per_ci'    => $bq_per_ci,
        'hr_per_day'   => $hr_per_day,
        'hr_per_min'   => $hr_per_min,
        'hr_per_sec'   => $hr_per_sec,
    );

    #
    # 'unit' objects
    #
    # Use $<unit>->power_of_10('<power>') as a key of
    # %{$metric_pref->list}, then the fetched value is
    # an object of the 'metric_pref' class, e.g. $nano, $micro, etc.
    #
    $nrg->name('electron-volt');
    $nrg->symbol('eV');
    $nrg->power_of_10(6); # MeV only
    $nrg->symb($metric_pref->list->{$nrg->power_of_10}->symbol.$nrg->symbol);
    $nrg->factor($metric_pref->list->{$nrg->power_of_10}->factor);
    $curr->name('ampere');
    $curr->symbol('A');
    $curr->power_of_10(-6); # uA only
    $curr->symb($metric_pref->list->{$curr->power_of_10}->symbol.$curr->symbol);
    $curr->factor($metric_pref->list->{$curr->power_of_10}->factor);
    $power->name('watt');
    $power->symbol('W');
    $power->symbol_recip($power->symbol.'^-1');
    $power->power_of_10($nrg->power_of_10 + $curr->power_of_10);
    $power->symb(
        $metric_pref->list->{$power->power_of_10}->symbol.
        $power->symbol
    );
    $power->symb_recip($power->symb.'^-1');
    $power->factor($metric_pref->list->{$power->power_of_10}->factor);
    $dim->name('meter');
    $dim->symbol('m');
    $dim->power_of_10('-2'); # e.g. -2 for cm, cm^2, and cm^3
    $dim->symb($metric_pref->list->{$dim->power_of_10}->symbol.$dim->symbol);
    $dim->factor($metric_pref->list->{$dim->power_of_10}->factor);
    $len->name('meter');
    $len->symbol($dim->symbol);
    $len->symbol_recip($dim->symbol.'^-1');
    $len->symb($dim->symb);
    $len->symb_recip($dim->symb.'^-1');
    $len->factor($dim->factor);
    $area->name('square-meter');
    $area->symbol($dim->symbol.'^2');
    $area->symbol_recip($dim->symbol.'^-2');
    $area->symb($dim->symb.'^2');
    $area->symb_recip($dim->symb.'^-2');
    $area->factor( ($dim->factor)**2 ); # Fortran exponentiation parlance
    $vol->name('cubic-meter');
    $vol->symbol($dim->symbol.'^3');
    $vol->symbol_recip($dim->symbol.'^-3');
    $vol->symb($dim->symb.'^3');
    $vol->symb_recip($dim->symb.'^-3');
    $vol->factor( ($dim->factor)**3 );
    $mass->name('gram');
    $mass->symbol('g');
    $mass->symbol_recip($mass->symbol.'^-1');
    $mass->power_of_10(0); # e.g. 0 for g, -3 for mg, 3 for kg
    $mass->symb($metric_pref->list->{$mass->power_of_10}->symbol.$mass->symbol);
    $mass->symb_recip($mass->symb.'^-1');
    $mass->factor($metric_pref->list->{$mass->power_of_10}->factor);
    # Densities
    $mass_dens->symbol($mass->symbol.' '.$vol->symbol_recip);
    $mass_dens->symb($mass->symb.' '.$vol->symb_recip);
    $mass_dens->factor($vol->factor / $mass->factor);
    $num_dens->symbol($vol->symbol_recip);
    $num_dens->symb($vol->symb_recip);
    $num_dens->factor($vol->factor);
    # Mole
    $mol->name('mole');
    $mol->symbol('mol');
    $mol->symbol_recip($mol->symbol.'^-1');
    $mol->power_of_10(0); # e.g. 0 for mol, -3 for mmol, 3 for kmol
    $mol->symb($metric_pref->list->{$mol->power_of_10}->symbol.$mol->symbol);
    $mol->symb_recip($mol->symb.'^-1');
    $mol->factor($metric_pref->list->{$mol->power_of_10}->factor);
    $molar_mass->symbol($mass->symbol.' '.$mol->symbol_recip);
    $molar_mass->symb($mass->symb.' '.$mol->symb_recip);
    $molar_mass->factor($mol->factor / $mass->factor);
    # Activity
    $act->sel(0); # 0: Bq, 1: Ci
    if ($act->sel == 0) {
        $act->name('becquerel');
        $act->symbol('Bq');
        $act->power_of_10(9); # e.g. 9 for GBq
    }
    elsif ($act->sel == 1) {
        $act->name('curie');
        $act->symbol('Ci');
        $act->power_of_10('bq_per_ci'); # A special key of %{$metric_pref->list}
    }
    $act->symb($metric_pref->list->{$act->power_of_10}->symbol.$act->symbol);
    $act->factor($metric_pref->list->{$act->power_of_10}->factor);
    $sp_act->symbol($act->symb.' '.$mass->symbol_recip);
    $sp_act->symb($act->symb.' '.$mass->symb_recip);
    $sp_act->factor($mass->factor / $act->factor);
    # Temperature
    $temp->sel(0); # 0: K, 1: degC
    $temp->symbol('K');
    $temp->symbol_recip($temp->symbol.'^-1');
    if ($temp->sel == 0) {
        $temp->name('kelvin');
        $temp->symb($temp->symbol);
        $temp->power_of_10('kelv'); # See %{$metric_pref->list}
    }
    elsif ($temp->sel == 1) {
        $temp->name('celsius');
        $temp->symb('degC');
        $temp->power_of_10('kelv_to_cels'); # See %{$metric_pref->list}
    }
    $temp->symb_recip($temp->symb.'^-1');
    $temp->factor($metric_pref->list->{$temp->power_of_10}->factor);
    # Thermal conductivity
    $therm_cond->symbol(
        $power->symbol.' '.$len->symbol_recip.' '.$temp->symbol_recip
    );
    $therm_cond->symb($power->symb.' '.$len->symb_recip.' '.$temp->symb_recip);
    $therm_cond->factor($len->factor / $power->factor); # DON'T USE $temp->factor
    # Time regimes
    $time->sel(1); # 0: Day, 1: Hour, 2: Minute, 3: Second
    $time->symbol('h');
    if ($time->sel == 0) {
        $time->name('day');
        $time->symb('d');
        $time->power_of_10('hr_per_day');
    }
    elsif ($time->sel == 1) {
        $time->name('hour');
        $time->symb($time->symbol);
        $time->power_of_10(0);
    }
    elsif ($time->sel == 2) {
        $time->name('minute');
        $time->symb('min');
        $time->power_of_10('hr_per_min');
    }
    elsif ($time->sel == 3) {
        $time->name('second');
        $time->symb('s');
        $time->power_of_10('hr_per_sec');
    }
    $time->factor($metric_pref->list->{$time->power_of_10}->factor);

    #
    # 'time_frame' objects
    # > Time frames expressed in "hour" are used for calculations and,
    #   those expressed in the unit cvt according to $time->sel
    #   are used for printing.
    # > Many other time frames such as $t_dec, $t_pro, and $t_del
    #   are defined in fix_time_frames() to reflect a possible change
    #   in $t_irr->to in overwrite_param().
    #
    $t_tot->from(0);
    $t_tot->to(400); # Hour
    $t_irr->from(0);
    $t_irr->to(72); # == end of irradiation

    #
    # 'math_constant' object
    #
    $const->avogadro(6.02214e+23); # Num substance/mol
    $const->coulomb(6.2415e+18);   # Num electrons/coulomb

    #
    # 'geometry' object
    #
    %{$geom->shape_opt} = (
        0 => 'Right circular cylinder',
        1 => 'Conical frustum (aka truncated cone)',
    );

    #
    # 'nuclide' objects
    #

    # Z=8: O
    %{$o->nat_occ_isots} = (
        o16 => $o16,
        o17 => $o17,
        o18 => $o18,
    );
    $o->name('oxygen');
    $o->symb('O');
    $o->atomic_num(8);
    $o16->mass_num(16);
    $o17->mass_num(17);
    $o18->mass_num(18);
    foreach my $key (keys %{$o->nat_occ_isots}) {
        my $isot = $o->nat_occ_isots->{$key};
        $isot->name($o->name.'-'.$isot->mass_num);
        $isot->symb($o->symb.'-'.$isot->mass_num);
        $isot->flag($key);
    }
    # http://www.ciaaw.org/oxygen.htm
    $o16->amt_frac(0.99757);
    $o17->amt_frac(0.0003835);
    $o18->amt_frac(0.002045);
    $o16->molar_mass(15.994914620);
    $o17->molar_mass(16.999131757);
    $o18->molar_mass(17.999159613);
    # Populate the mass_frac attribute using amt_frac and molar_mass.
    calc_elem_wgt_molar_mass_and_isot_mass_fracs(
        $o,
        'amt_frac',
        'quiet',
    );

    # Z=42: Mo
    %{$mo->nat_occ_isots} = (
        mo92  => $mo92,
        mo94  => $mo94,
        mo95  => $mo95,
        mo96  => $mo96,
        mo97  => $mo97,
        mo98  => $mo98,
        mo99  => $mo99,
        mo100 => $mo100,
    );
    $mo->name('molybdenum');
    $mo->symb('Mo');
    $mo->atomic_num(42);
    $mo92->mass_num(92);
    $mo94->mass_num(94);
    $mo95->mass_num(95);
    $mo96->mass_num(96);
    $mo97->mass_num(97);
    $mo98->mass_num(98);
    $mo99->mass_num(99);
    $mo100->mass_num(100);
    foreach my $key (keys %{$mo->nat_occ_isots}) {
        my $isot = $mo->nat_occ_isots->{$key};
        $isot->name($mo->name.'-'.$isot->mass_num);
        $isot->symb($mo->symb.'-'.$isot->mass_num);
        $isot->flag($key);
    }
    # http://www.ciaaw.org/molybdenum.htm
    $mo92->amt_frac(0.14649);
    $mo94->amt_frac(0.09187);
    $mo95->amt_frac(0.15873);
    $mo96->amt_frac(0.16673);
    $mo97->amt_frac(0.09582);
    $mo98->amt_frac(0.24292);
    $mo99->amt_frac(0.00000);
    $mo100->amt_frac(0.09744);
    $mo92->molar_mass(91.906808);
    $mo94->molar_mass(93.905085);
    $mo95->molar_mass(94.905839);
    $mo96->molar_mass(95.904676);
    $mo97->molar_mass(96.906018);
    $mo98->molar_mass(97.905405);
    $mo99->molar_mass(98.9077119);
    $mo100->molar_mass(99.907472);
    calc_elem_wgt_molar_mass_and_isot_mass_fracs(
        $mo,
        'amt_frac',
        'quiet',
    );

    # It is the decay constant that cancels out with a time quantity
    # expressed in hour and, as such, the decay constant must also be the
    # one expressed in hour. The decay constant below is therefore defined
    # as ln(2) divided by the physical half-life expressed in hour.
    $mo99->half_life_phy(65.94); # Hour
    $mo99->dec_const(log(2) / $mo99->half_life_phy); # Perl log == natural log
    $mo99->negatron_dec_1->negatron_line_1(0.450);   # MeV
    $mo99->negatron_dec_1->gamma_line_1(0.740);
    $mo99->negatron_dec_1->gamma_line_2(0.181);
    $mo99->negatron_dec_1->branching_fraction(0.125); # Dimensionless
    $mo99->negatron_dec_2->negatron_line_1(1.214);
    $mo99->negatron_dec_2->gamma_line_1(0.778);
    $mo99->negatron_dec_2->branching_fraction(0.875);

    # Z=43: Tc
    %{$tc->nat_occ_isots} = (
        tc99  => $tc99,
        tc99m => $tc99m,
    );
    $tc->name('technetium');
    $tc->symb('Tc');
    $tc->atomic_num(43);
    $tc99->mass_num(99);
    $tc99m->mass_num('99m');
    foreach my $key (keys %{$tc->nat_occ_isots}) {
        my $isot = $tc->nat_occ_isots->{$key};
        $isot->name($tc->name.'-'.$isot->mass_num);
        $isot->symb($tc->symb.'-'.$isot->mass_num);
        $isot->flag($key);
    }
    $tc99->amt_frac(0.00000);
    $tc99m->amt_frac(0.00000);
    $tc99->molar_mass(98.9062547);
    $tc99m->molar_mass($tc99->molar_mass);
    $tc99m->avg_dose(740e+06);
    $tc99m->half_life_phy(6.01); # Hour
    $tc99m->dec_const(log(2) / $tc99m->half_life_phy);
    $tc99m->gamma_dec1->gamma_line_1(0.1405);
    $tc99m->gamma_dec1->branching_fraction(0.890);

    # Z=74: W
    %{$w->nat_occ_isots} = (
        w180 => $w180,
        w182 => $w182,
        w183 => $w183,
        w184 => $w184,
        w186 => $w186,
    );
    $w->name('tungsten');
    $w->symb('W');
    $w->atomic_num(74);
    $w->mass_dens(19.25e+6); # g m^-3
    $w180->mass_num(180);
    $w182->mass_num(182);
    $w183->mass_num(183);
    $w184->mass_num(184);
    $w186->mass_num(186);
    foreach my $key (keys %{$w->nat_occ_isots}) {
        my $isot = $w->nat_occ_isots->{$key};
        $isot->name($w->name.'-'.$isot->mass_num);
        $isot->symb($w->symb.'-'.$isot->mass_num);
        $isot->flag($key);
    }
    # http://www.ciaaw.org/tungsten.htm
    $w180->amt_frac(0.0012);
    $w182->amt_frac(0.2650);
    $w183->amt_frac(0.1431);
    $w184->amt_frac(0.3064);
    $w186->amt_frac(0.2843);
    $w180->molar_mass(179.94671); # g mol^-1
    $w182->molar_mass(181.948204);
    $w183->molar_mass(182.950223);
    $w184->molar_mass(183.950931);
    $w186->molar_mass(185.95436);
    calc_elem_wgt_molar_mass_and_isot_mass_fracs(
        $w,
        'amt_frac',
        'quiet',
    );

    # Targetry (1/2) Converter
    $converter->name('converter target');
    $converter->molar_mass($w->wgt_avg_molar_mass);
    $converter->mass_dens($w->mass_dens);
    $converter->geom->shape('0'); # 0:RCC
    $converter->geom->rad1(0.02); # m
    $converter->geom->hgt(0.001); # m
    $converter->therm_cond(173);  # W m^-1 K^-1
    $converter->melt_point(3695.15);
    $converter->boil_point(6203.15);
    calc_vol_and_mass($converter);

    # Targetry (2/2) Mo target
    $mo_tar->name('molybdenum target');
    $mo_tar->geom->shape(1);     # 0:RCC, 1:TRC
    $mo_tar->geom->rad1(0.0015); # Bottom radius; in m
    $mo_tar->geom->rad2(0.006);  # Top radius; in m
    $mo_tar->geom->hgt(0.01);    # In m
    %{$mo_tar->is_enri_opt} = (
        0 => 'Nonenriched Mo',
        1 => 'Enriched in Mo-100',
    );
    $mo_tar->is_enri(1);
    $mo100->enri(0.9900);
    %{$mo_tar->mole_ratio_o_to_mo_opt} = (
        0 => 'Metallic Mo',
        2 => 'MoO2',
        3 => 'MoO3',
    );
    $mo_tar->mole_ratio_o_to_mo(0);
    assign_symb_to_mo_tar();
    @{$mo_tar->of_int} = (0, 2, 3); # Number of oxygen constituents
    $mo_met->name('metallic Mo');
    $mo_met->symb('Mo_met');
    $mo_diox->name('molybdenum dioxide');
    $mo_diox->symb('MoO2');
    $mo_triox->name('molybdenum trioxide');
    $mo_triox->symb('MoO3');

    #
    # 'mc_sim' object
    #
    $phits->path('./phits_np1e7/');
    $phits->bname('tar_e');
    $phits->flag->spectrum('_spt');
    $phits->flag->track('_trk');
    $phits->flag->err('_err');
    $phits->ext->inp('inp');
    $phits->ext->out('out');
    $phits->ext->ang('ang');

    #
    # 'cross_section' object
    #
    $xs->inp('./xs/xs_mogn.dat');
    $xs->is_chk(1);

    #
    # 'gnuplot' objects
    #
    $gp->cmt_symb($symb->hash);
    $gp->cmt_border->len(69);
    $gp->cmt_border->equals(
        $gp->cmt_symb.($symb->equals x $gp->cmt_border->len)
    );
    $gp->cmt_border->dash($gp->cmt_symb.($symb->dash x $gp->cmt_border->len));
    $gp->cmt_border->plus($gp->cmt_symb.($symb->plus x $gp->cmt_border->len));
    $gp->col->header_sep(' '.$symb->vert_bar.' ');
    $gp->end_of->block("\n");
    $gp->end_of->dataset("\n\n");
    $gp->end_of->file($gp->cmt_symb."eof");
    %{$gp->col->content_sep_opt} = (
        0 => $symb->space,
        1 => $symb->tab, # spreadsheet-friendly
        2 => $symb->comma,
    );
    $gp->col->content_sep(0);
    $gp->ext->dat('dat');
    $gp->ext->tmp('tmp');
    $gp->ext->inp('gp');
    $gp->missing_dat_str('NaN');
    $gp->cmd('gnuplot');
    my $prepender = sprintf("%s ", $gp->cmt_symb);
    $mark_time_frame_of->non(''); # Write nothing
    $mark_time_frame_of->eoi($prepender.'End of targetry irradiation');
    $mark_time_frame_of->eop($prepender.'End of Mo taget processing');
    $mark_time_frame_of->eod('End of Tc-99m generator delivery');
    $mark_time_frame_of->elu($prepender.'Tc-99m elution');

    #
    # 'comma_separated_values' object
    #
    $csv->sep($symb->comma);
    $csv->is_quoted(1);
    $csv->quoted('') if not $csv->is_quoted;
    $csv->quoted($symb->double_quote) if $csv->is_quoted;
    $csv->ext('csv');

    #
    # 'ms_excel' object
    #
    $excel->ext->xls('xls');
    $excel->ext->xlsx('xlsx');

    #
    # 'linac' object
    #
    $linac->name('Electron linear accelerator');
    $linac->op_nrg(35);            # MeV
    $linac->op_avg_beam_curr(260); # uA

    #
    # 'chemical_processing' object
    #
    %{$chem_proc->predef_opt} = (
        0 => 'Predefined $chem_proc attributes',
        1 => 'Overwrite',
    );
    $chem_proc->is_overwrite(0);
    $chem_proc->time_required->to(12);
    $chem_proc->mo99_loss_ratio_at_eop(0.2);
    $chem_proc->tc99m_loss_ratio_at_eop($chem_proc->mo99_loss_ratio_at_eop);

    #
    # 'tc99m_generator' object
    #
    $tc99m_gen->delivery_time->to(12);
    %{$tc99m_gen->predef_opt} = (
        0 => 'Predefined $tc99m_gen attributes',
        1 => 'Overwrite',
    );
    $tc99m_gen->is_overwrite(0);
    %{$tc99m_gen->elu_discard_opt} = (
        1 => 'Use the first Tc-99m eluate',
        2 => 'Discard',
    );
    $tc99m_gen->elu_ord_from(2); # elu_discard_opt
    $tc99m_gen->elu_eff(0.7);
    $tc99m_gen->elu_itv(24);
    $tc99m_gen->shelf_life(240);

    #
    # 'actdyn' objects
    #
    $actdyn->path('./results/');
    $actdyn->bname('actdyn');
    $actdyn->flag->chk('chk');
    $actdyn->ext->chk('dat');
    @{$actdyn->nrgs_of_int} = (20..70); # MeV
    $actdyn->pwm->is_chk(1);
    $actdyn->pwm->is_show_gross(0);

    $mo99_act_nrg_tirr->is_calc_disp(1);
    @{$mo99_act_nrg->tirrs_of_int} = (50, 72, 100, 200, 300, 400);

    #
    # 'country' object
    #
    %{$country->list} = (
        world => { name => 'World',  obj => $world },
        usa   => { name => 'USA',    obj => $usa   },
        eur   => { name => 'Europe', obj => $eur   },
        jpn   => { name => 'Japan',  obj => $jpn   },
    );
    $world->tc99m_demand_num->yearly();
    $jpn->tc99m_demand_num->yearly(1e6);
    $usa->tc99m_demand_num->yearly();
    $eur->tc99m_demand_num->yearly();

    foreach my $k (sort keys %{$country->list}) {
        # Redirection
        my $nation = $country->list->{$k}{obj};
        $nation->name($country->list->{$k}{name});
        next if not $nation->tc99m_demand_num->yearly;

        # Tc-99m demand in number of procedures
        # per month, per week, and per day
        $nation->tc99m_demand_num->monthly(
            $nation->tc99m_demand_num->yearly
            / 12
        );
        $nation->tc99m_demand_num->weekly(
            $nation->tc99m_demand_num->yearly
            / 52 # 52.1429
        );
        $nation->tc99m_demand_num->daily(
            $nation->tc99m_demand_num->weekly
            / 7
        );
    };

    return;
}


sub actdyn_preproc {
    # """actdyn preprocessor"""

    my $run_opts_href = shift;

    # Populate the object attributes, some of which are overwritable
    # in overwrite_param() placed at the bottom of the current routine.
    populate_attrs();

    # Chosen units
    my %units = (
        nrg => {
            name => "Energy",
            symb => $nrg->symb,
        },
        cur => {
            name => "Electric current",
            symb => $curr->symb,
        },
        power => {
            name => "Electric power",
            symb => $power->symb,
        },
        dim => {
            name => "Dimension",
            symb => $dim->symb,
        },
        len => {
            name => "Length",
            symb => $len->symb,
        },
        area => {
            name => "Area",
            symb => $area->symb,
        },
        vol => {
            name => "Volume",
            symb => $vol->symb,
        },
        num_dens => {
            name => "Number density",
            symb => $num_dens->symb,
        },
        mass => {
            name => "Mass",
            symb => $mass->symb,
        },
        mass_dens => {
            name => "Mass density",
            symb => $mass_dens->symb,
        },
        mol => {
            name => "Mole",
            symb => $mol->symb,
        },
        molar_mass => {
            name => "Molar mass",
            symb => $molar_mass->symb,
        },
        act => {
            name => "Activity",
            symb => $act->symb,
        },
        sp_act => {
            name => "Specific activity",
            symb => $sp_act->symb,
        },
        temp => {
            name => "Temperature",
            symb => $temp->symb,
        },
        therm_cond => {
            name => "Thermal conductivity",
            symb => $therm_cond->symb,
        },
        time => {
            name => "Time",
            symb => $time->symb,
        },
    );
    my @names;
    push @names, $units{$_}{name} for keys %units;
    my @lengthiest = sort { length $b <=> length $a } @names;
    my $conv = '%-'.(length $lengthiest[0]).'s';

    say $disp->border->dash;
    foreach my $k (sort keys %units) {
        printf(
            "%s$conv => %s\n",
            $disp->indent,
            $units{$k}{name},
            $units{$k}{symb},
        );
    }
    say $disp->border->dash;

    # Parameter selection
    printf("%sDefault parameters have been set.\n", $disp->indent)
        if $run_opts_href->{is_dflt};
    overwrite_param()
        if not $run_opts_href->{is_dflt};
    correct_trailing_path_sep(
        $phits,
        $actdyn,
    );
    $gp->col->content_sep($gp->col->content_sep_opt->{$gp->col->content_sep});

    # Fix some time frames after the parameter overwriting.
    fix_time_frames();
    fix_max_ord_of_tc99m_elution();

    return;
}


sub actdyn_main {
    # """actdyn main routine"""

    # Mo-99/Tc-99m activity dynamics calculation
    calc_mo100_num_dens();
    calc_mo99_tc99m_actdyn_data();

    return;
}


sub actdyn_postproc {
    # """actdyn postprocessor"""

    my $prog_info_href = shift;

    # Convert the units of calculated quantities;
    # e.g. Bq --> GBq, g m^-3 --> g cm^-3
    convert_units();

    # Write the calculation results to data files.
    gen_mo99_tc99m_actdyn_data($prog_info_href);
    calc_num_of_required_linacs(); # Reporting file

    return;
}


sub actdyn_runner {
    # """actdyn running routine"""

    if (@ARGV) {
        my %prog_info = (
            titl       => basename($0, '.pl'),
            expl       => 'A Mo-99/Tc-99m activity dynamics simulator',
            vers       => $VERSION,
            date_last  => $LAST,
            date_first => $FIRST,
            auth       => {
                name => 'Jaewoong Jang',
#                posi => '',
#                affi => '',
                mail => 'jangj@korea.ac.kr',
            },
        );
        my %cmd_opts = ( # Command-line opts
            inter   => qr/-?-i\b/i,
            dflt    => qr/-?-d\b/i,
            nofm    => qr/-?-nofm\b/i,
            verbose => qr/-?-verb(?:ose)?\b/i,
            nopause => qr/-?-nopause\b/i,
        );
        my %run_opts = ( # Program run opts
            is_inter   => 0,
            is_dflt    => 0,
            is_nofm    => 0,
            is_verbose => 0,
            is_nopause => 0,
        );

        # ARGV validation and parsing
        validate_argv(\@ARGV, \%cmd_opts) if @ARGV;
        parse_argv(\@ARGV, \%cmd_opts, \%run_opts) if @ARGV;

        # Notification - beginning
        show_front_matter(\%prog_info, 'prog', 'auth', 'no_trailing_blkline')
            unless $run_opts{is_nofm};

        # actdyn routines
        if ($run_opts{is_inter} or $run_opts{is_dflt}) {
            actdyn_preproc(\%run_opts);
            actdyn_main();
            actdyn_postproc(\%prog_info) if $actdyn->is_run;
        }

        # Notification - end
        show_elapsed_real_time("\n");
        pause_terminal("Press enter to exit...")
            unless $run_opts{is_nopause};
    }

    system("perldoc \"$0\"") if not @ARGV;

    return;
}


actdyn_runner();
__END__


=head1 NAME

actdyn - A Mo-99/Tc-99m activity dynamics simulator

=head1 SYNOPSIS

    perl actdyn.pl [-i|-d] [-nofm] [-verbose] [-nopause]

=head1 DESCRIPTION

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

=head1 OPTIONS

    -i
        Run on the interactive mode.

    -d
        Run on the default mode.

    -nofm
        The front matter will not be displayed at the beginning of the program.

    -verbose (short form: -verb)
        Calculation processes will be displayed.

    -nopause
        The shell will not be paused at the end of the program.
        Use it for a batch run.

=head1 EXAMPLES

    perl actdyn.pl -d -nopause
    perl actdyn.pl -verbose

=head1 REQUIREMENTS

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

=head1 SEE ALSO

L<actdyn on GitHub|https://github.com/jangcom/actdyn>

L<actdyn-generated data in a paper: I<Phys. Rev. Accel. Beams> B<20>, 104701 (Figs. 4, 5, 12, and 13)|https://link.aps.org/doi/10.1103/PhysRevAccelBeams.20.104701>

=head1 AUTHOR

Jaewoong Jang <jangj@korea.ac.kr>

=head1 COPYRIGHT

Copyright (c) 2016-2019 Jaewoong Jang

=head1 LICENSE

This software is available under the MIT license;
the license information is found in 'LICENSE'.

=cut
