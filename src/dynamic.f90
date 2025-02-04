!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!   EVB-QMDFF - RPMD molecular dynamics and rate constant calculations on
!               black-box generated potential energy surfaces
!
!   Copyright (c) 2021 by Julien Steffen (steffen@pctc.uni-kiel.de)
!                         Stefan Grimme (grimme@thch.uni-bonn.de) (QMDFF code)
!
!   Permission is hereby granted, free of charge, to any person obtaining a
!   copy of this software and associated documentation files (the "Software"),
!   to deal in the Software without restriction, including without limitation
!   the rights to use, copy, modify, merge, publish, distribute, sublicense,
!   and/or sell copies of the Software, and to permit persons to whom the
!   Software is furnished to do so, subject to the following conditions:
!
!   The above copyright notice and this permission notice shall be included in
!   all copies or substantial portions of the Software.
!
!   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
!   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
!   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
!   THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
!   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
!   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
!   DEALINGS IN THE SOFTWARE.
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!
!     #################################################################
!     ##                                                             ##
!     ##  program dynamic  --  run molecular verlet dynamics         ##
!     ##                                                             ##
!     #################################################################
!
!
!     "dynamic" computes a molecular dynamics trajectory with EVB-QMDFF.
!
!
program dynamic
use general
use evb_mod

implicit none
integer i,istep,nstep,asciinum,j,k,nat,l
integer mode,next,check,readstatus
integer::qmdffnumber,idum
logical::analyze  ! if temperature etc shall be calculated during verlet step
integer parameters!natoms,parameters  !mod
real*8 dt,dtdump,lengthUnits,energyUnits
real(kind=8),dimension(:),allocatable::int_coord  ! for internal coordinates
real(kind=8),dimension(:,:),allocatable::xyz2
real(kind=8),dimension(:,:),allocatable::ts_coordinates_a,ts_coordinates2_a
logical exist,query
real(kind=8)::etot,epot,ekin  ! the total energy for testing
real(kind=8),allocatable::centroid(:,:)  ! the RPMD centroid
real(kind=8)::dist,dist_first,dist_last
real(kind=8),allocatable::force_avg(:)
real(kind=8),allocatable::force_avgs(:)
real(kind=8),allocatable::len_avg(:),len_avgs(:)
integer::afm_avg
integer::afm_segment
integer::afm_segment_avg
logical::afm_second
character(len=120)::xyzfile

real(kind=8),dimension(:,:,:),allocatable::derivs  ! the derivatives of the potential 
                                             !   energy for all beads at once
real(kind=8)::k_B ! inverse temperature and boltzmann constant
real(kind=8)::afm_force   ! the returned force on the AFM atom
parameter(k_B=0.316679D-5)  ! the boltzmann constant in au/kelvin
real(kind=8)::dt_info ! time in ps for information
real(kind=8)::num_measure  ! how many times the temperature is measured..
integer::nbeads_store   ! the stored number of beads (RPMD)
character(len=20) keyword
character(len=80)::names,a80,coul_method
character(len=120) record
character(len=50)::fix_file ! file with numbers of fixed atoms
character(len=120) string
character(len=1)::qmdffnum
character(len=40)::commarg ! string for command line argument
integer::istat,readstat
character(len=10)::ensemble ! which thermodynamic ensemble is used
! For box simulations with periodic boundary conditions
real(kind=8)::coul_cut,vdw_cut
logical::periodic,ewald,ewald_brute,zahn
real(kind=8)::ewald_accuracy
real(kind=8)::boxlen_x,boxlen_y,boxlen_z
real(kind=8)::e_pot_avg,e_kin_avg,e_tot_avg  ! averages for energies
real(kind=8)::e_cov_avg,e_noncov_avg 
character(len=50)::baro_name,coul_name ! which barostat shall be used
!     periodic box size
real(kind=8)::xmin,ymin,zmin,xmax,ymax,zmax
!     for read in of local RPMD activation
character(len=1)::at_index(200)
character(len=20)::act_number
!   for umbrella samplings 
real(kind=8),allocatable::dxi_act(:,:)
real(kind=8)::xi_ideal,xi_real
integer::bias_mode
integer::round,constrain
!     the evb-qmdff input
character(len=70)::fffile1,fffile2,fffile3,fileinfo,filets
character(len=70)::filets2
character(len=60)::test,soschl_pre1,soschl_hess
logical::exists,has_next,par_soschl,coupl1
logical::evb1,evb2,evb3,ffname1,ffname2,ffname3,defqmdff
logical::path_struc,path_energy,coupl,ts_xyz,params
logical::keyword1,keyword2,keyword3
!     the MPI rank (here always 0)
integer::rank

!
!     Set MPI rank to zero for this program
!
rank=0
!
!     no MPI is used
!
use_mpi=.false.
!
!     Activate the RPMD switch for correct application of gradient calculations
!
use_rpmd=.true.

!
!     no RPMDrate is used
!
use_rpmdrate = 0
!
!
!     set up the structure and molecular mechanics calculation
!
call initial(rank)
!
!     print out help informations if -help or -h is given as command line argument
!     call the respective subroutine, else, show infos about the possibility
!
if (rank .eq. 0) then
   call get_command_argument(1, commarg)
   if (trim(commarg) .eq. "-help" .or. trim(commarg) .eq. "-h") then
      call help("dynamic")
      stop
   else
      write(*,*) "To show some basic infos about the program and a list of all"
      write(*,*) "used keywords in it, type 'dynamic.x -help' or 'dynamic.x -h'."
      write(*,*)
   end if
end if

!
!     Read keywords from the key-file
!
call getkey(rank)

!
!      Option to change the atomic mass of one element in the system
!
change_mass=.false.
!do i = 1, nkey
!   next = 1
!   record = keyline(i)
!   call gettext (record,keyword,next)
!   call upcase (keyword)
!   string = record(next:120)
!   if (keyword(1:20) .eq. 'CHANGE_MASS ') then
!       read(record,*) names,elem_mass,newmass
!       change_mass=.true.
!   end if
!end do

!if (change_mass) then
!   write(*,*) "The CHANGE_MASS option was activated!"
!   write(*,*) "All ", elem_mass," atoms will be assinged a mass of ",newmass, " a.u."
!end if



!
!     Read in the start structure for dynamics (keyword: XYZSTART)
!
call getxyz
!
!     Read in the QMDFF and EVB terms
!
call read_pes(rank)
!
!     initialize the temperature, pressure and coupling baths
!
kelvin = 0.0d0
atmsph = 0.0d0
isothermal = .false.
isobaric = .false.
writestat=.true. ! print MD statistics!
allocate(centroid(3,natoms))

!-----------------------Dynamic-inputparameters--------------------------
!
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     Read the general dynamic input parameters   !!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!   the default values:
!
nbeads=1  
ensemble="NVE"
nstep=0
dt=1.d0
dtdump=1.d0
bias_mode=0  ! no umbrella sampling as default
allocate(dxi_act(3,natoms))
!
!    Read in the commands from the keyfile 
!
do i = 1, nkey
   next = 1
   record = keyline(i)
   call gettext (record,keyword,next)
   call upcase (keyword)
   string = record(next:120)
!    Name of xyz input file (for information) 
   if (keyword(1:11) .eq. 'XYZSTART ') then
      read(record,*) names,xyzfile
!    Number of RPMD beads
   else if (keyword(1:20) .eq. 'BEAD_NUMBER ') then
      read(record,*) names,nbeads
!    Which thermodynamic ensemble is used
   else if (keyword(1:13) .eq. 'ENSEMBLE ') then
      read(record,*) names,ensemble
!    How many MD steps are simulated 
   else if (keyword(1:11) .eq. 'STEPS ') then
      read(record,*) names,nstep
!    Time step of the Verlet algorithm
   else if (keyword(1:11) .eq. 'DELTAT ') then
      read(record,*) names,dt
!    Time between two xyz trajectory dumps
   else if (keyword(1:11) .eq. 'TDUMP ') then
      read(record,*) names,dtdump
   end if
end do
!
!     Check the the read in settings 
!
nvt=.false.
npt=.false.
if (nbeads .lt. 1) then
   write(*,*) "The number of RPMD beads must be positive!"
   call fatal
end if
call upcase(ensemble)
if (ensemble .eq. "NVT") then
   nvt=.true.
else if (ensemble .eq. "NPT") then
   npt=.true.
else if (ensemble .eq. "NVE") then
   nve=.true.
else 
   write(*,*) "No valid thermodynamic ensemble given! Choose either"
   write(*,*) " NVE, NVT or NPT."
   call fatal
end if
if (nstep .lt. 1) then
   write(*,*) "The number of MD timesteps must be greater than zero!"
   call fatal
end if
if (dt .lt. 1D-5) then
   write(*,*) "The MD timestep is too small to be useful!"
   call fatal
end if

!
!    The write frequency
!
iwrite = nint(dtdump/(dt))


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     Read the parameter for the NVE ensemble     !!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

if (nve) then
   thermostat = 0
   kelvin=0
   thermo="none"
   periodic=.false.
   box_walls=.false.
   boxlen_x=0.d0
   boxlen_y=0.d0
   boxlen_z=0.d0
   ewald=.false.
   zahn=.true.
   coul_method="ZAHN"
   coul_cut=10.d0
   vdw_cut=10.d0
   andersen_step=70
   nose_q=100.d0
   do i = 1, nkey
      next = 1
      record = keyline(i)
      call gettext (record,keyword,next)
      call upcase (keyword)
      call upcase (record)
      string = record(next:120)
      if (trim(adjustl(record(1:11))) .eq. 'NVE {' .or. trim(adjustl(record(1:11))) &
                 &  .eq. 'NVE{') then
         do j=1,nkey-i+1
            next=1
            record = keyline(i+j)
            call gettext (record,keyword,next)
            call upcase (keyword)
!    If periodic, the dimensions of the simulation box
            if (keyword(1:13) .eq. 'PERIODIC ') then
               read(record,*,iostat=readstat) names,boxlen_x,boxlen_y,boxlen_z
               periodic=.true.
               if (readstat .ne. 0) then
                  write(*,*) "Correct format: PERIODIC [xlen,ylen,zlen (A)]"
                  call fatal
               end if
!    If a box with hard walls, the dimensions
            else if (keyword(1:11) .eq. 'BOX_WALLS ') then
               read(record,*,iostat=readstat) names,boxlen_x,boxlen_y,boxlen_z
               box_walls=.true.
               if (readstat .ne. 0) then
                  write(*,*) "Correct format: BOX_WALLS [xlen,ylen,zlen (A)]"
                  call fatal
               end if
!    For the periodic coulomb interactions
            else if (keyword(1:11) .eq. 'COULOMB ') then
               read(record,*,iostat=readstat) names,a80
               if (readstat .ne. 0) then
                  write(*,*) "Correct format: COULOMB [method]"
                  call fatal
               end if
               call upcase(a80)
               if (a80 .eq. "PPPME") then
                  ewald=.true.
                  write(*,*) "The Particle Particle Particle Mesh Ewald (PPPME) method"
                  write(*,*) " will be used for the handling of Coulomb interactions."
                  write(*,*) "Please choose another method, the implementation is not complete!"
                  call fatal
               end if
               if (a80 .eq. 'ZAHN ') then
                  zahn=.true.
               end if
               coul_method=a80
!    The cutoff distance for Coulomb interactions
            else if (keyword(1:14) .eq. 'COUL_CUTOFF ') then
               read(record,*,iostat=readstat) names,coul_cut
               if (readstat .ne. 0) then
                  write(*,*) "Correct format: COUL_CUTOFF [value (A)]"
                  call fatal
               end if
!    The cutoff distance for VDW interactions
            else if (keyword(1:13) .eq. 'VDW_CUTOFF ') then
               read(record,*,iostat=readstat) names,vdw_cut
               if (readstat .ne. 0) then
                  write(*,*) "Correct format: VDW_CUTOFF [value (A)]"
                  call fatal
               end if
            end if
            if (keyword(1:13) .eq. '}') exit
            if (j .eq. nkey-i) then
               write(*,*) "The NVE section has no second delimiter! (})"
               call fatal
            end if
         end do
         exit
      end if
   end do

end if

!write(*,*) periodic
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     Read the parameter for the NVT ensemble     !!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


if (nvt) then
!
!    The default values:
!
   kelvin=0
   thermo="none"
   periodic=.false.
   box_walls=.false.
   boxlen_x=0.d0
   boxlen_y=0.d0
   boxlen_z=0.d0
   ewald=.false.
   zahn=.true.
   coul_method="ZAHN"
   coul_cut=10.d0
   vdw_cut=10.d0
   andersen_step=70
   nose_q=100.d0
   do i = 1, nkey
      next = 1
      record = keyline(i)
      call gettext (record,keyword,next)
      call upcase (keyword)
      call upcase (record)
      string = record(next:120)
      if (trim(adjustl(record(1:11))) .eq. 'NVT {' .or. trim(adjustl(record(1:11))) &
                 &  .eq. 'NVT{') then
         do j=1,nkey-i+1
            next=1
            record = keyline(i+j)
            call gettext (record,keyword,next)
            call upcase (keyword)
!    The simulation temperature
            if (keyword(1:11) .eq. 'TEMP ') then
               read(record,*,iostat=readstat) names,kelvin
               if (readstat .ne. 0) then
                  write(*,*) "Correct format: TEMP [temperature (K)]"
                  call fatal
               end if
!    The thermostat
            else if (keyword(1:20) .eq. 'THERMOSTAT ') then
               read(record,*,iostat=readstat) names,thermo
               if (readstat .ne. 0) then
                  write(*,*) "Correct format: THERMOSTAT [thermostat]"
                  call fatal
               end if
               call upcase(thermo)
!    If periodic, the dimensions of the simulation box
            else if (keyword(1:13) .eq. 'PERIODIC ') then
               read(record,*,iostat=readstat) names,boxlen_x,boxlen_y,boxlen_z
               periodic=.true.
               if (readstat .ne. 0) then
                  write(*,*) "Correct format: PERIODIC [xlen,ylen,zlen (A)]"
                  call fatal
               end if
!    If a box with hard walls, the dimensions
            else if (keyword(1:11) .eq. 'BOX_WALLS ') then
               read(record,*,iostat=readstat) names,boxlen_x,boxlen_y,boxlen_z
               box_walls=.true.
               if (readstat .ne. 0) then
                  write(*,*) "Correct format: BOX_WALLS [xlen,ylen,zlen (A)]"
                  call fatal
               end if
!    For the periodic coulomb interactions 
            else if (keyword(1:11) .eq. 'COULOMB ') then
               read(record,*,iostat=readstat) names,a80
               if (readstat .ne. 0) then
                  write(*,*) "Correct format: COULOMB [method]"
                  call fatal
               end if
               call upcase(a80)
               if (a80 .eq. "PPPME") then
                  ewald=.true.
                  write(*,*) "The Particle Particle Particle Mesh Ewald (PPPME) method"
                  write(*,*) " will be used for the handling of Coulomb interactions."
                  write(*,*) "Please choose another method, the implementation is not complete!"
                  call fatal
               end if
               if (a80 .eq. 'ZAHN ') then
                  zahn=.true.
               end if
               coul_method=a80
!    The cutoff distance for Coulomb interactions
            else if (keyword(1:14) .eq. 'COUL_CUTOFF ') then
               read(record,*,iostat=readstat) names,coul_cut
               if (readstat .ne. 0) then
                  write(*,*) "Correct format: COUL_CUTOFF [value (A)]"
                  call fatal
               end if
!    The cutoff distance for VDW interactions
            else if (keyword(1:13) .eq. 'VDW_CUTOFF ') then
               read(record,*,iostat=readstat) names,vdw_cut
               if (readstat .ne. 0) then
                  write(*,*) "Correct format: VDW_CUTOFF [value (A)]"
                  call fatal
               end if
!    How often the Andersen thermostat velocity rescaling is applied
            else if (keyword(1:16) .eq. 'ANDERSEN_STEP ') then
               read(record,*,iostat=readstat) names,andersen_step
               if (readstat .ne. 0) then
                  write(*,*) "Correct format: ANDERSEN_STEP [No. of steps]"
                  call fatal
               end if
!    The damping factor for the Nose-Hoover thermostat
            else if (keyword(1:13) .eq. 'NOSE_DAMP ') then
               read(record,*,iostat=readstat) names,nose_q
               if (readstat .ne. 0) then
                  write(*,*) "Correct format: NOSE_DAMP [integer (>1)]"
                  call fatal
               end if
            end if
            if (keyword(1:13) .eq. '}') exit
            if (j .eq. nkey-i) then
               write(*,*) "The NVT section has no second delimiter! (})"
               call fatal
            end if
         end do
         exit
      end if
   end do
!
!     Check the the read in settings 
!
   if (kelvin .lt. 0.d0) then
      write(*,*) "Give a positive temperature!"
      call fatal
   end if
     
   if (trim(thermo) .eq. "ANDERSEN") then
      thermostat = 1
   else if (trim(thermo) .eq. "NOSE-HOOVER") then
      thermostat = 2
   else 
      write(*,*) "No availiable thermostat was chosen! Only the Andersen"
      write(*,*) "thermostat and the Nose-Hoov(e-Chain) thermostats are availiable at the moment." 
      write(*,*) "Add the keyword THERMOSTAT!"
      call fatal
   end if   
end if


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     Read the parameter for the NPT ensemble     !!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

if (npt) then
   kelvin=0
   pressure=0
   thermo="none"
   barostat=1  ! berendsen is default
   periodic=.false.
   box_walls=.false.
   boxlen_x=0.d0
   boxlen_y=0.d0
   boxlen_z=0.d0
   ewald=.false.
   zahn=.true.
   coul_method="ZAHN"
   coul_cut=10.d0
   vdw_cut=10.d0
   andersen_step=70
   nose_q=100.d0
   nose_tau=4000.d0
   andersen_step=70

   do i = 1, nkey
      next = 1
      record = keyline(i)
      call gettext (record,keyword,next)
      call upcase (keyword)
      call upcase (record)
      string = record(next:120)
      if (trim(adjustl(record(1:11))) .eq. 'NPT {' .or. trim(adjustl(record(1:11))) &
                 &  .eq. 'NPT{') then
         do j=1,nkey-i+1
            next=1
            record = keyline(i+j)
            call gettext (record,keyword,next)
            call upcase (keyword)
            if (keyword(1:11) .eq. 'TEMP ') then
               read(record,*) names,kelvin
            else if (keyword(1:11) .eq. 'PRES ') then
               read(record,*) names,pressure
            else if (keyword(1:20) .eq. 'THERMOSTAT ') then
               read(record,*) names,thermo
               call upcase(thermo)
            else if (keyword(1:11) .eq. 'BAROSTAT ') then
               read(record,*) names,baro_name
               call upcase(baro_name)
                if (baro_name .eq. "BERENDSEN") then
                   barostat=1
                else if (baro_name .eq. "NOSE-HOOVER") then
                   barostat=2
                else
                   write(*,*) "No valid barostat chosen! BERENDSEN and  & 
                            & NOSE-HOOVER are available!"
                end if
            else if (keyword(1:13) .eq. 'PERIODIC ') then
               read(record,*,iostat=readstat) names,boxlen_x,boxlen_y,boxlen_z
               periodic=.true.
            else if (keyword(1:11) .eq. 'COULOMB ') then
               read(record,*) names,a80
               call upcase(a80)
               if (a80 .eq. "PPPME") then
                  ewald=.true.
                  write(*,*) "The Particle Particle Particle Mesh Ewald (PPPME) method"
                  write(*,*) " will be used for the handling of Coulomb interactions."
                  write(*,*) "Please choose another method, the implementation is not complete!"
                  call fatal
               end if
               if (a80 .eq. 'ZAHN ') then
                  zahn=.true.
               end if
               coul_method=a80
            else if (keyword(1:11) .eq. 'COUL_CUTOFF ') then
               read(record,*) names,coul_cut
            else if (keyword(1:11) .eq. 'VDW_CUTOFF ') then
               read(record,*) names,vdw_cut
            else if (keyword(1:16) .eq. 'ANDERSEN_STEP ') then
               read(record,*) names,andersen_step
            else if (keyword(1:13) .eq. 'NOSE_DAMP ') then
               read(record,*) names,nose_q
            else if (keyword(1:11) .eq. 'BARO_DAMP ') then
               read(record,*) names,nose_tau
            end if
            if (keyword(1:13) .eq. '}') exit
            if (j .eq. nkey-i) then
               write(*,*) "The NPT section has no second delimiter! (})"
               call fatal
            end if
         end do
      end if
   end do
!
!     Check the the read in settings 
!
   if (kelvin .lt. 0.d0) then
      write(*,*) "Give a positive temperature!"
      call fatal
   end if
   if (pressure .lt. 0.d0) then
      write(*,*) "Give a positive pressure!"
      call fatal
   end if 
   call upcase (thermo)
   if (trim(thermo) .eq. "ANDERSEN") then 
      thermostat = 1
   else if (trim(thermo) .eq. "NOSE-HOOVER") then
      thermostat = 2
   else
      write(*,*) "No availiable thermostat was chosen! Only the Andersen"
      write(*,*) "thermostat and the Nose-Hoov(e-Chain) thermostats are availiable at the moment."
      write(*,*) "Add the keyword THERMOSTAT!"
      call fatal
   end if
   if (.not. periodic) then
      write(*,*) "The NPT ensemble can only be simulated in periodic systems!"
      call fatal
   end if
!
!     set Nose-Hoover friction decay rate as mulitple of timestep
!
   nose_q=nose_q*dt/2.41888428E-2   
end if

!
!     define the beta parameter for thermodynamics
!
beta=1.d0/(kelvin*k_B)
!
!     convert timestep to atomic units!
!
dt_info=0.001*dt ! time in ps for information write out
dt = dt/2.41888428E-2

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     Read parameters for force/mechanochem.      !!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
add_force=.false.
do i = 1, nkey
   next = 1
   record = keyline(i)
   call gettext (record,keyword,next)
   call upcase (keyword)
   call upcase (record)
   string = record(next:120)
   if (trim(adjustl(record(1:11))) .eq. 'FORCE {' .or. trim(adjustl(record(1:11))) .eq. 'FORCE{') then
      add_force=.true.
      do j=1,nkey-i+1
         next=1
         record = keyline(i+j)
         call gettext (record,keyword,next)
         call upcase (keyword)
!     First atom on which force is applied: index and force vector
         if (keyword(1:11) .eq. 'VEC1 ') then
            read(record,*) names,force1_at,force1_k,force1_v(1),force1_v(2),force1_v(3)
!     Second atom on which force is applied: index and force vector
         else if (keyword(1:11) .eq. 'VEC2 ') then
            read(record,*) names,force2_at,force2_k,force2_v(1),force2_v(2),force2_v(3)
!     Start an atomic force microscope (AFM) simulation run
         else if (keyword(1:11) .eq. 'AFM_RUN ') then
            afm_run=.true.
            add_force = .false.  ! no usual force addition in the case of an AFM run
!     For AFM simulation: index of fixed atom on surface
         else if (keyword(1:11) .eq. 'AFM_FIX ') then
            read(record,*) names,afm_fix_at
!     For AFM simulation: index of moved atom on tip and force vector
         else if (keyword(1:11) .eq. 'AFM_MOVE ') then
            read(record,*) names,afm_move_at,afm_move_dist,afm_move_v(1),afm_move_v(2),afm_move_v(3)
!     How often status information for AFM shall be printed out
         else if (keyword(1:11) .eq. 'AFM_AVG ') then
            read(record,*) names,afm_avg
!     If two separate reactions shall be monitored, give the number of MD steps after which the 
!     second event shall be looked at
         else if (keyword(1:15) .eq. 'AFM_SECOND ') then
            read(record,*) names,afm_segment
            afm_second=.true.
         end if
         if (keyword(1:13) .eq. '}') exit
         if (j .eq. nkey-i) then
            write(*,*) "The FORCE section has no second delimiter! (})"
            call fatal
         end if
      end do
   end if
end do
if (add_force) then
!
!     normalize the force vectors
!
   force1_v=force1_v/(sqrt(force1_v(1)**2+force1_v(2)**2+force1_v(3)*2))
   force2_v=force2_v/(sqrt(force2_v(1)**2+force2_v(2)**2+force2_v(3)*2))
!
!     transform units of force constants from Newton to atomic units 
!
   if ((force1_at .eq. 0) .or. (force1_at .gt. natoms) .or.&
              &  (force2_at .eq. 0) .or. (force2_at .gt. natoms)) then
      write(*,*) "ERROR! The atoms at which the force shall be applied are"
      write(*,*) " not part of the system!"
      call fatal
   end if
  !  write(*,*) "FORCE setup:"
  !  write(*,*) "At atom",force1_at," a force of",force1_k," N is applied."
  !  write(*,*) "At atom",force2_at," a force of",force2_k," N is applied."
   force1_k=force1_k*newton2au
   force2_k=force2_k*newton2au
!
!     Open file in which distances between the atoms with attached force will 
!     be written  
!
   write(*,*) "Distances between atoms with attached force will be written to"
   write(*,*) "file force_distances.dat"
   open(unit=78,file="force_distances.dat",status="replace")
   write(78,*) "# distances between the atoms with attached force, in Angstrom:"
end if
!
!     If the AFM run was activated: read in the fixed and moving atom 
!     and initialize the settings 
!

if (afm_run) then
   afm_avg=50
   afm_second=.false.
   afm_fix_at=0
   afm_move_at=0
   
   do i = 1, nkey
      next = 1
      record = keyline(i)
      call gettext (record,keyword,next)
      call upcase (keyword)
      string = record(next:120)
!
!     Ordering: [Atom index] [Force (N)] [Vector (x,y,z)]
!
      if (keyword(1:11) .eq. 'AFM_FIX ') then
         read(record,*,iostat=readstat) names,afm_fix_at
         if (readstat .ne. 0) then
            write(*,*) "Please check AFM_FIX keyword!"
            call fatal
         end if
      else if (keyword(1:11) .eq. 'AFM_MOVE ') then
         read(record,*,iostat=readstat) names,afm_move_at,afm_move_dist,afm_move_v(1), &
                   & afm_move_v(2),afm_move_v(3)
         if (readstat .ne. 0) then
            write(*,*) "Please check AFM_MOVE keyword!"
            call fatal
         end if
      else if (keyword(1:11) .eq. 'AFM_AVG ') then
         read(record,*,iostat=readstat) names,afm_avg
         if (readstat .ne. 0) then
            write(*,*) "Please check AFM_AVG keyword!"
            call fatal
         end if
!
!     If two separate reactions shall be monitored, give the number of MD steps after which the 
!     second event shall be looked at
!
      else if (keyword(1:15) .eq. 'AFM_SECOND ') then
         read(record,*,iostat=readstat) names,afm_segment
         if (readstat .ne. 0) then
            write(*,*) "Please check AFM_SECOND keyword!"
            call fatal
         end if
         afm_second=.true.
      end if
   end do
!
!     Check if obligatory AFM settings were read in
!
   if (afm_fix_at .eq. 0) then
      write(*,*) "Please add the keyword AFM_FIX for the AFM simulation!"
      call fatal
   end if
   if (afm_move_at .eq. 0) then
      write(*,*) "Please add the keyword AFM_MOVE for the AFM simulation!"
      call fatal
   end if

!
!     normalize the force vector
!
   afm_move_v=afm_move_v/(sqrt(afm_move_v(1)**2+afm_move_v(2)**2+afm_move_v(3)**2))
   if ((afm_fix_at .eq. 0) .or. (afm_fix_at .gt. natoms) .or.&
              &  (afm_move_at .eq. 0) .or. (afm_move_at .gt. natoms)) then
      write(*,*) "ERROR! The atoms at which the force shall be applied are"
      write(*,*) " not part of the system!"
      call fatal
   end if
!
!     the AFM bias force (default: 10nN strength)
!
   afm_k=7E-9
   afm_k=afm_k*newton2au
!
!     open file in which AFM distances as well as forces will be written
!
   write(*,*) "AFM distances and forces will be written to file "
   write(*,*) "afm_log.dat"
   open(unit=79,file="afm_log.dat",status="replace")
   write(79,*) "# time (ps)    AFM distance (Angstrom)   AFM force (nN)"
!
!     allocate array with averaged force values during dynamics 
!
   allocate(force_avg(afm_avg))
   allocate(force_avgs(nstep/(afm_avg*iwrite)*2))
   allocate(len_avg(afm_avg))
   allocate(len_avgs(nstep/(afm_avg*iwrite)*2))
   afm_segment_avg=afm_segment/(afm_avg*iwrite)
end if



!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!     Read more detailed/special MD parameters    !!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!
!     If a periodic calculation is ordered, look if the Smooth particle mesh Ewald 
!     method shall be compared with the full Ewald sum for benchmark
!
ewald_brute=.false.
if (periodic) then
   do i = 1, nkey
      next = 1
      record = keyline(i)
      call gettext (record,keyword,next)
      call upcase (keyword)
      string = record(next:120)
      if (keyword(1:11) .eq. 'EWALD_FULL ') then
         ewald_brute=.true.
         write(*,*) "The keyword EWALD_FULL was activated! A single MD step will be "
         write(*,*) "calculated and the SPME method will be compared with the exact "
         write(*,*) "brute-force Ewald summation."
         exit
      end if
   end do

end if

!
!      Evaluate time-dependent values of chosen coordinates
!
eval_coord=.false.
eval_step = 1
do i = 1, nkey
   next = 1
   record = keyline(i)
   call gettext (record,keyword,next)
   call upcase (keyword)
   string = record(next:120)
   if (keyword(1:20) .eq. 'EVAL_COORD ') then
      read(record,*,iostat=readstat) names,eval_step
      if (readstat .ne. 0) then
         write(*,*) "Correct format: EVAL_COORD [write frequency (number)]"
         call fatal
      end if
      write(*,*) "The keyword EVAL_COORD was activated! All coordinates listed "
      write(*,*) " in the file 'coord_eval.inp' will be read in and their values "
      write(*,*) " will be written out every ",eval_step," steps to the file "
      write(*,*) " coord_eval.dat"
      call ev_coord_init  
      eval_coord=.true.
      exit
   end if
end do


!
!      Read in velocities from file as starting for momentum
!
read_vel=.false.
do i = 1, nkey
   next = 1
   record = keyline(i)
   call gettext (record,keyword,next)
   call upcase (keyword)
   string = record(next:120)
   if (keyword(1:20) .eq. 'READ_VEL ') then
      read_vel=.true.
      write(*,*) "Starting velocities/momenta will be read in from file"
      write(*,*) " 'velocity_start.dat'!"
   end if
end do

if (read_vel) then
   allocate(vel_start(natoms,3))
   open(unit=291,file="velocity_start.dat",status="old")
   read(291,*) 
   read(291,*)
   do i=1,natoms
      read(291,*) idum,idum,vel_start(i,:)
   end do

   close(291)
end if
!
!      Calculate averaged kinetic energy per atom for a subgroup of the system
!
calc_ekin=.false.
do i = 1, nkey
   next = 1
   record = keyline(i)
   call gettext (record,keyword,next)
   call upcase (keyword)
   string = record(next:120)
   if (keyword(1:20) .eq. 'AVG_EKIN ') then
      calc_ekin=.true.
   end if
end do


if (calc_ekin) then
   write(*,*) "The averaged kinetic energy for a subgroup of the system shall"
   write(*,*) " be calculated! The list of atoms will be read in from file 'list_ekin.dat'."
   open(unit=23,file="list_ekin.dat",status="old",iostat=readstat)
   if (readstat .ne. 0) then
      write(*,*) "No file 'list_ekin.dat' found, the kinetic energy will be calculated"
      write(*,*) " for all atoms."
      do i=1,natoms
         ekin_atoms(i)=i
      end do
      ekin_num=natoms
   else 
      k=1
      do
         read(23,*,iostat=readstat) ekin_atoms(k)
         if (ekin_atoms(k) .gt. natoms) then
            write(*,*) "ERROR! One atom in 'list_ekin.dat' is out-of-bounds!"
            call fatal
         end if

         if (readstat .ne. 0) exit
         k=k+1
      end do
      ekin_num=k-1
      if (ekin_num .gt. natoms) then
         write(*,*) "ERROR! The number of atoms given in 'list_ekin.dat' is too large!"
         call fatal
      end if
          write(*,'(a,i5,a)') "In total Ekin will be calculated for, ",ekin_num,&
               & " atoms." 
      close(23)
   end if
   ekin_avg=0.d0
   ekin2_avg=0.d0
   write(*,*) "For each time step, the kinetic energy will be written to file 'ekin_step.dat'"
   open(unit=156,file="ekin_step.dat",status="replace")
   write(156,*) "#  centroid estimation     virial theorem"
end if
!
!     Activate if you want to control if the total energy is conserved
!
energycon=.false.
do i = 1, nkey
    next = 1
    record = keyline(i)
    call gettext (record,keyword,next)
    call upcase (keyword)
    string = record(next:120)
    if (keyword(1:11) .eq. 'E_CON ') then
       energycon=.true.
    end if
end do
!
!     Activate the additional output of gradients and velocities every tdump
!     time step 
!
verbose=.false.
do i = 1, nkey
    next = 1
    record = keyline(i)
    call gettext (record,keyword,next)
    call upcase (keyword)
    string = record(next:120)
    if (keyword(1:20) .eq. 'OUTPUT_VERBOSE ') then
       verbose=.true.
    end if
end do

!
!     Activate for separate printout of covalent and noncovalent fractions 
!     of the QMDFF potential energy
!
energysplit=.false.
do i = 1, nkey
    next = 1
    record = keyline(i)
    call gettext (record,keyword,next)
    call upcase (keyword)
    string = record(next:120)
    if (keyword(1:16) .eq. 'SPLIT_ENERGY ') then
       energysplit=.true.
    end if
end do

!
!     store the number of beads during structure gen.
!
nbeads_store=nbeads
!
!     Option for fixing of distinct atoms in order to make e.g. metal slab calculations 
!     possible 
!
fix_atoms=.false.
do i = 1, nkey
    next = 1
    record = keyline(i)
    call gettext (record,keyword,next)
    call upcase (keyword)
    string = record(next:120)
    if (keyword(1:20) .eq. 'FIX_ATOMS ') then
       fix_atoms=.true.
       read(record,*) names,fix_file
    end if
    if (fix_atoms) then
       inquire(file=fix_file,exist=exist)
       if (.not. exist) then
          if (rank .eq. 0) then
             write(*,*) "ERROR! The file ",fix_file," with the fixed atoms is not present!"
          end if
          call fatal
       end if
       allocate(fix_list(1000))
!
!     Read in list with fixed atoms 
! 
       open(unit=213,file=fix_file,status="old")
       k=1
       do
          read(213,*,iostat=readstat) fix_list(k)
          if (readstat .ne. 0) exit
          k=k+1
       end do
       fix_num=k-1
       write(*,'(a,i5,a)') " The FIXED_ATOMS option was activated! In total, ",fix_num,&
            & " atoms"
       write(*,*) " will be hold fixed."
       exit 
    end if
end do
!-----------------------Initialize-MD-Run--------------------------
!
!
!     If the system shall be described periodic of with hard box walls : 
!     Shift the system to the first octand
!     and check if the given box lengths are large enough to contain it     
!
if (periodic .or. box_walls) then
   xmin=minval(x(:))
   ymin=minval(y(:))
   zmin=minval(z(:))

   x(:)=x(:)-xmin
   y(:)=y(:)-ymin
   z(:)=z(:)-zmin
   
   xmax=maxval(x(:))
   ymax=maxval(y(:))
   zmax=maxval(z(:))
   if (xmax .gt. boxlen_x) then
      write(*,*) "ERROR! You have chosen a periodic/hard box, but the elongation"
      write(*,*) " of the given structure in x-direction is too large!"
      call fatal
   else if (ymax .gt. boxlen_y) then
      write(*,*) "ERROR! You have chosen a periodic/hard box, but the elongation"
      write(*,*) " of the given structure in y-direction is too large!"
      call fatal
   else if (zmax .gt. boxlen_z) then
      write(*,*) "ERROR! You have chosen a periodic/hard box, but the elongation"
      write(*,*) " of the given structure in z-direction is too large!"
      call fatal
   end if
!
!     Place the initial structure(s) in the center of the box!
!   
   x(:)=x(:)+0.5d0*(boxlen_x-xmax)
   y(:)=y(:)+0.5d0*(boxlen_y-ymax)
   z(:)=z(:)+0.5d0*(boxlen_z-zmax)
!
!     If a barostat shall be applied, set the initial values 
!
   vel_baro=0.d0
end if
if (npt .and. .not. periodic) then
   write(*,*) "The NPT ensemble can only be used for periodic systems!"
   call fatal
end if
!
!     initialize and setup dynamics
!     --> allocate arrays for positions (q_i) and momenta (p_i) and 
!     convert to bohr 
!
allocate(q_i(3,natoms,nbeads_store),p_i(3,natoms,nbeads_store))
do k=1,nbeads
   do i=1,natoms
      q_i(1,i,k)=x(i)/bohr
      q_i(2,i,k)=y(i)/bohr
      q_i(3,i,k)=z(i)/bohr
   end do
end do
!
!     For NPT ensemble: convert the pressure unit
!
if (npt) then
   pressure=pressure/prescon
end if
!
!     For periodic systems: convert the box lengths to bohr as well!
!
if (periodic) then
   boxlen_x=boxlen_x/bohr
   boxlen_y=boxlen_y/bohr
   boxlen_z=boxlen_z/bohr

   call set_periodic(periodic,boxlen_x,boxlen_y,boxlen_z,ewald,zahn,ewald_brute,coul_cut,vdw_cut)  
     ! set global variables in qmdff module..
end if
!
!     For systems with hard box walls: convert the box length to bohr
if (box_walls) then
   walldim_x=boxlen_x/bohr
   walldim_y=boxlen_y/bohr
   walldim_z=boxlen_z/bohr
end if
! 
allocate(derivs(3,natoms,nbeads))
!
!     For the AFM experiment: store the initial position of anchor atom
!
if (afm_run) then
   afm_move_first(:)=q_i(:,afm_move_at,1)
end if
!
!     If the internal coordinates shall be written to file, open it
!
if (int_coord_plot) open(unit=191,file="int_coord.out",status="unknown")
!
!-----------------------Print-Information-for-run------------------------
!
!
write(*,*) "----------------------------------------------------------"
write(*,*) "The following molecular dynamics job will be started:"
write(*,*) " - Input geometry: ",trim(xyzfile)
if (nbeads .eq. 1) then
   write(*,*) " - Number of RPMD beads: 1 (classical)"
else 
   write(*,'(a,i4)') "  - Number of RPMD beads: ",nbeads
end if
if (ensemble .eq. "NVT") then
   write(*,*) " - Thermodynamic ensemble: NVT "
else if (ensemble .eq. "NPT") then
   write(*,*) " - Thermodynamic ensemble: NpT "
else if (ensemble .eq. "NVE") then
   write(*,*) " - Thermodynamic ensemble: NVE "
end if
write(*,'(a,i10)') "  - Number of simulated MD steps:",nstep
write(*,'(a,f12.5)') "  - MD time step (fs):",dt*2.41888428E-2
write(*,'(a,f15.5)') "  - Total simulated timescale (ps):",dt*2.41888428E-2*nstep/1000.d0
write(*,'(a,f13.5,a)') "  - Trajectory frames will be written every",dtdump," fs"
if (nvt) then
   write(*,'(a,f12.5)') "  - Desired temperature (K): ",kelvin
   write(*,*) " - The temperature will be applied by the ",trim(thermo)," thermostat"
   if (periodic) then
      write(*,*) " - The periodic box has the dimensions (x,y,z) (Angstron):"
      write(*,'(a,f14.6,f14.6,f14.6)') "    ",boxlen_x*bohr,boxlen_y*bohr,boxlen_z*bohr
      write(*,*) " - Long range Coulomb interactions treated with: ",trim(coul_method)
   end if
   if (box_walls) then
      write(*,*) " - The hard walled box has the dimensions (x,y,z) (Angstron):"
      write(*,'(a,f14.6,f14.6,f14.6)') "    ",boxlen_x*bohr,boxlen_y*bohr,boxlen_z*bohr
   end if
   write(*,'(a,f11.3,a)') "  - (Short) Coulomb interactions have a cutoff of ",coul_cut, " A"
   write(*,'(a,f11.3,a)') "  - VDW interactions have a cutoff of ",vdw_cut, " A"
   if (thermo .eq. "ANDERSEN") then
      write(*,'(a,i6,a)') "  - The Andersen velocity rescaling is done every ",andersen_step," MD steps"
   end if 
   if (thermo .eq. "NOSE-HOOVER") then
      write(*,'(a,f12.5,a)') "  - The Nose-Hoover thermostat damping Q is: ",nose_q," time steps"    
   end if 
end if

if (npt) then
   write(*,'(a,f12.5)') "  - Desired temperature (K): ",kelvin
   write(*,'(a,f12.5)') "  - Desired pressure (atm): ",pressure*prescon
   write(*,*) " - The temperature will be applied by the ",trim(thermo)," thermostat"
   write(*,*) " - The pressure will be applied by the ",trim(baro_name), " barostat"
   write(*,*) " - The periodic box has the initial dimensions (x,y,z) (Angstron):"
   write(*,'(a,f14.6,f14.6,f14.6)') "    ",boxlen_x*bohr,boxlen_y*bohr,boxlen_z*bohr
   write(*,*) " - Long range Coulomb interactions treated with: ",trim(coul_method)
   if (box_walls) then
      write(*,*) " - The hard walled box has the dimensions (x,y,z) (Angstron):"
      write(*,'(a,f14.6,f14.6,f14.6)') "    ",boxlen_x*bohr,boxlen_y*bohr,boxlen_z*bohr
   end if
   write(*,'(a,f11.3,a)') "  - (Short) Coulomb interactions have a cutoff of ",coul_cut, " A"
   write(*,'(a,f11.3,a)') "  - VDW interactions have a cutoff of ",vdw_cut, " A"
   if (thermo .eq. "ANDERSEN") then
      write(*,'(a,i6,a)') "  - The Andersen velocity rescaling is done every ",andersen_step," MD steps"
   end if
   if (thermo .eq. "NOSE-HOOVER") then
      write(*,'(a,f12.5,a)') "  - The Nose-Hoover thermostat damping Q is: ",nose_q," time steps"
   end if
end if


!
!     call the initialization routine
!

call mdinit(derivs,xi_ideal,dxi_act,bias_mode)
!
!     if you want to control if the total energy is conserved
!

if (verbose .or. energycon) then
   open(unit=123,file="md_energies.dat",status="unknown")
   write(123,*) "#   MD step   pot.energy    kin.energy   total energy "
   e_pot_avg=0.d0
   e_kin_avg=0.d0
   e_tot_avg=0.d0
end if
if (energysplit .eqv. .true.) then
   write(*,*) "Fractions of covalent and noncovalent energy will be written to file "
   write(*,*) " 'energy_split.dat'."
   open(unit=124,file="energy_split.dat",status="unknown") 
   write(124,*) "#   MD step    covalent energy       noncovalent energy      total energy"
end if
!
!     write trajectory in tdump-intervals: open file
!
open(unit=28,file="trajectory.xyz",status="unknown")
!
if (verbose) then
!     verbose output: also write gradients of all atoms to file 
   open(unit=29,file="md_gradients.dat",status="unknown")
!     verbose output: also write velocities of all atoms to file 
   open(unit=30,file="md_velocities.dat",status="unknown")
end if

write(*,*) 
write(*,*)  " . ...- -... --.- -- -.. ..-. ..-."
!
!    Measure the needed time for dynamic steps
!
call cpu_time(time1)
!
!     integrate equations of motion to take a time step
!
if (afm_run) afm_steps=nstep
l=1
j=1
if (afm_run) force_avg(:)=0
if (afm_run) len_avg(:)=0

!
!     Open files for temperature etc. printouts
!
if (.not. nve) then
   open(unit=236,file="temperature.dat",status="unknown")
end if
!write(*,*) "INFO: Here are bond lengths written to bonds.log!"
!write(*,*) " delete this if no longer needed!"
write(*,*) "Performing MD ...."
if (npt) then
   write(*,*) "  Step    Epot(Hartree)    T(K)      Volume(A^3)     Press.(atm)   density(g/cm^3)"   
!
!    Calculate the mass of the system for density calculations
!
   mass_tot=sum(mass)
end if
temp_test=0.d0
num_measure=real(nstep)/real(iwrite)
do istep = 1, nstep
   analyze=.false.
!
!     Write the trajectory frame every iwrite timesteps
!
   if (mod(istep,iwrite) .eq. 0) then
      analyze=.true.
   end if
   round=0
   constrain=-1
   call verlet (istep,dt,derivs,epot,ekin,afm_force,xi_ideal,xi_real,dxi_act, &
            & round,constrain,analyze)
!
!     TEST: write out bondlengths to bonds.log
!

   afm_force=afm_force/bohr  ! convert to Angstrom 
!
!     if a molecular force experiment is conducted, write out 
!     the distance between the end atoms 
!
   if (add_force) then
      call get_centroid(centroid)
      if (mod(istep,iwrite) .eq. 0) then
         write(78,*) dist(force1_at,force2_at,centroid)*bohr 
      end if
      if (istep .eq. 1) dist_first=dist(force1_at,force2_at,centroid)*bohr
      if (istep .eq. nstep) dist_last=dist(force1_at,force2_at,centroid)*bohr
   end if 

   if (afm_run) then
      call get_centroid(centroid)
      if (mod(istep,iwrite) .eq. 0) then
         write(79,*) istep*dt*2.41888428E-2*1E-3,dist(afm_fix_at,afm_move_at,centroid)*bohr,afm_force*1E9
         force_avg(l)=force_avg(l)+afm_force*1E9/afm_avg
         len_avg(l)=len_avg(l)+dist(afm_fix_at,afm_move_at,centroid)*bohr/afm_avg
         l=l+1
         if (l .eq. afm_avg) then
            l=1
            force_avgs(j)=sum(force_avg)
            force_avg(:)=0
            len_avgs(j)=sum(len_avg)
            len_avg(:)=0
            j=j+1
         end if
      end if
   end if

   if (energycon .or. verbose) then
      if (mod(istep,iwrite) .eq. 0) then
         write(123,*) istep,epot,ekin,epot+ekin
         e_pot_avg=e_pot_avg+epot
         e_kin_avg=e_kin_avg+ekin
         e_tot_avg=e_tot_avg+epot+ekin
      end if
   end if
   if (energysplit) then
      if (mod(istep,iwrite) .eq. 0) then
         write(124,*) istep,e_cov_split,e_noncov_split,epot+ekin
         e_cov_avg=e_cov_avg+e_cov_split
         e_noncov_avg=e_noncov_avg+e_noncov_split
      end if
   end if   

end do
if (add_force) close(78)
if (add_force) then
   write(*,*) "Mechanochemistry results:"
   write(*,'(a,f30.6,a)') "  Length of the molecule at the beginning: ",dist_first," Angstrom."
   if (dist_last .gt. 1E7) dist_last=1E7
   write(*,'(a,f20.6,a)') "  Length of the molecule at the end: ",dist_last," Angstrom."

end if

!
!     If the kinetic energy shall be calculated: average over all beads, atoms and steps 
!
if (calc_ekin) then
   write(*,*) nstep,nbeads,ekin_num
   ekin_avg=ekin_avg/(nstep*nbeads**2*ekin_num)
   ekin2_avg=ekin2_avg/(nstep*ekin_num)
   write(*,*) "The average kinetic energy per atom/bead (centroid) is:"
   write(*,*) ekin_avg,"Hartee"
   write(*,*) ekin_avg*hartree,"kcal/mol"
   write(*,*) ekin_avg*hartree*joule,"kJ/mol"
   write(*,*)
   write(*,*) "The average kinetic energy per atom/bead (virial theorem) is:"
   write(*,*) ekin2_avg,"Hartee"
   write(*,*) ekin2_avg*hartree,"kcal/mol"
   write(*,*) ekin2_avg*hartree*joule,"kJ/mol"
   write(*,*) 
   write(*,*) "The analytical kinetic energy value of 3/2 kT is:"
   write(*,*) 1.5*1.380649E-23/4.3597447E-18*kelvin,"Hartree"
   write(*,*) 1.5*1.380649E-23/4.3597447E-18*hartree*kelvin,"kcal/mol"
   write(*,*) 1.5*1.380649E-23/4.3597447E-18*hartree*joule*kelvin,"kJ/mol"
   close(156)
end if

close(236)
!
!     Evalue the AFM simulation run: average force and length profiles 
!     and determine the maximum force as well as the corresponding length
! 

if (afm_run) then
   open(unit=80,file="afm_averages.dat",status="replace")
   write(80,*) "# time (ps)      averaged force (nN)    averaged lengths (Angstrom)"
   do i=1,nstep/(afm_avg*iwrite)
      write(80,*) i*afm_avg*dt*2.41888428E-2*1E-3*iwrite,force_avgs(i),len_avgs(i)
   end do 
   close(80)
   write(*,*) "Averaged values for AFM forces and distances were"
   write(*,*) "written to file 'afm_averages.dat'."
   write(*,*)
   if (afm_second) then
      write(*,'(a,f14.7,a,f14.7,a)') " The first reaction is located at ",&
                  & maxval(force_avgs(1:afm_segment_avg))," nN at ",maxval(len_avgs(1:afm_segment_avg))," Angstrom."
      write(*,'(a,f14.7,a,f14.7,a)') " The second reaction is located at ",&
                  & maxval(force_avgs(afm_segment_avg:nstep/(afm_avg*iwrite)))," nN at ",& 
                  & maxval(len_avgs(afm_segment_avg:nstep/(afm_avg*iwrite)))," Angstrom."
   else 
      write(*,'(a,f14.7,a,f14.7,a)') " The maximum force recorded is ",&
                  & maxval(force_avgs(1:nstep/(afm_avg*iwrite)))," nN at ",&
                  & maxval(len_avgs(1:nstep/(afm_avg*iwrite)))," Angstrom."
      write(*,*) maxloc(force_avgs),maxloc(len_avgs)
   end if
end if
if (.not. nve) then 
   write(*,'(a,f12.5,a)') " The averaged measured temperature was:",temp_test/num_measure," K."
end if
if (energycon) then
   write(*,'(a,f16.8,a)') " The average value of the potential energy was: ",e_pot_avg/num_measure," Hartrees."
   write(*,'(a,f16.8,a)') " The average value of the kinetic energy was: ",e_kin_avg/num_measure," Hartrees."
   write(*,'(a,f16.8,a)') " The average value of the total energy was: ",e_tot_avg/num_measure," Hartrees."
end if
if (energysplit) then
   write(*,'(a,f16.8,a)') " The average value of the bonded pot. energy was: ",e_cov_avg/num_measure," Hartrees."
   write(*,'(a,f16.8,a)') " The average value of the nonbonded pot. energy was: ",e_noncov_avg/num_measure," Hartrees."
 
end if
if (eval_coord) close(141)
if (int_coord_plot) close(191)
!
!    calculate the needed time for dynamic steps
!
call cpu_time(time2)

duration=time2-time1
write(*,*)
write(*,'(A, F12.3, A)') " The calculation needed a time of",duration," seconds."
if (verbose) then
   write(*,*) " Trajectory written to 'trajectory.xyz', temperatures to 'temperature.dat',"
   write(*,*) " gradients to 'md_gradients.dat', velocities to 'md_velocities.dat', "
   write(*,*) " energies to 'md_energies.dat'."
else 
   if (nve) then
      write(*,*) " Trajectory written to 'trajectory.xyz'."
   else 
      write(*,*) " Trajectory written to 'trajectory.xyz', temperatures to 'temperature.dat'."
   end if
end if

write(*,*)

write(*,*) ".. .----. -- -.. --- -. . "
write(*,*) "Dynamic calculation successfully finished!"
if (energycon .eqv. .true.) then
   close(123)
end if
close(28)
close(29)
close(30)

end program dynamic

