Operation terminated by user during dlmread


In spm_opm_read_lvm (line 54)
data = dlmread(S.filename, '\t',S.headerlength,0);

In spm_opm_create>read_neuro1_data (line 630)
        [lbv] = spm_opm_read_lvm(args);

In spm_opm_create (line 91)
        S = read_neuro1_data(S);

In untitled (line 22)
D1            = spm_opm_create(S_create);
 

>> 
