subroutine ret_ssmis(tb,nchanl,n, &
     ssmis_las,ssmis_uas,ssmis_img,ssmis_env, &
     tpwmdl,ts5,cosza,pems5,clw,ierr)

! subprogram:    ret_ssmis    retrieve various parameters for SSMIS
! prgmmr: weng, okamoto     org: np23                date: 2005-03-22
!
! abstract: retrieve clw from sounding ch using only 50.3GHz channel 
!     retrieve clw from SSM/I-like channels after mimicing frequency
!
!     These algorithm are based on
!
!        "Effects of AMSU cross-scan Symmetry of brightness temperatures
!         on  retrieval of atmospheric and surface parameters" 
!
!     by Weng, F., R. R. Ferraro, and N. C. Grody, published in 
!     "Microwave Radiometry & Remote Sensing of the Earth Surface and Atmosphere"
!     Ed. P. Pampaloni and S. Paloscia, VSP, Netherlands, 255-262, 2000. 
!
!     tpw:: total precipitable water 
!     clw :: column cloud water ove ocean  [kg/m2]
!         range 0-6.0kg/m2, precision:0.5kg/m2
!         Weng et.al.,1997,J.Climate vol.10   
!
! program history log:
!     2003-12-27  okamoto
!     2004-07-12  okamoto - simplify rain identification
!     2005-10-07  Xu & Pawlak - add documentation. Also, per Fuzhong Weng, deleted
!                 code for retrieval based on ssmis_las instrument since
!                 algorithm is intented only for ssmis_img, fixed indentation 
!     2006-04-27  Derber - modify for single profile
!
! input argument list:
!     tb      - Observed brightness temperature [K]
!     nchanl  - number of channels per obs
!     ssmis_las    - logical true if ssmis_las (channel 1,2,3,4,5,6,7,24) is processed
!     ssmis_uas    - logical true if ssmis_uas (channel 19,20,21,22,23) is processed
!     ssmis_img    - logical true if ssmis_img (channel 8,9,10,11,17,18) is processed
!     ssmis_env    - logical true if ssmis_env (channel 12,13,14,15,16) is processed
!     cosza  - cos(zasat), zasat is local zenith angle
!     ts5    - sea surface temperature
!     pems5  - sea surface emissivity
!     tpwmdl    - column water vapor over ocean  [kg/m2]
! output argument list:
!     clw     - column cloud water vapor over ocean  [kg/m2]
!     ierr    - error flag
!               [0]pass or escape this subroutine without doing anything
!               [1]tbb gross error
!               [2]polarization gross erro
!
! attributes:
!     language: f90
!     machine:  ibm RS/6000 SP
!
!$$$
  use kinds, only: r_kind, i_kind
  use constants, only: two,three,zero,one,half,izero
  
  implicit none

! Declare passed variables
  integer(i_kind),intent(in)   ::nchanl,n
  real(r_kind),dimension(nchanl),intent(in)::tb
  real(r_kind),intent(in)::tpwmdl,ts5,cosza
  real(r_kind),dimension(nchanl),intent(in)::pems5
  logical,intent(in):: ssmis_las,ssmis_uas,ssmis_env,ssmis_img
  integer(i_kind),intent(out) ::ierr
  real(r_kind),intent(out)::clw

! Declare local variables
  real(r_kind)::coeabswv,coeabslw(3),coethkns(2)
  real(r_kind)::abswv,abslw,tau0
  real(r_kind)::rmis=-9.99e11_r_kind
  integer(i_kind) :: i,j
  integer(i_kind) :: iclwflg
  real(r_kind),parameter:: r285=285.0_r_kind
  real(r_kind),parameter:: r290=290.0_r_kind
  real(r_kind),dimension(7):: ap,bp,cp,dp,cp0,dp0,tby,tbx
  real(r_kind):: alg1,alg2,alg3,tpw
  real(r_kind):: seaice

  ierr = izero
  clw = rmis

  if(ssmis_img) then

!    ap and bp for the cloud liquid water mass absorption coefficients calculation 
     ap = (/7.80472_r_kind, 7.44254_r_kind, 6.76383_r_kind, 7.34409_r_kind, &
          8.55426_r_kind, 6.57813_r_kind,6.45397_r_kind/)
     bp = (/0.967519_r_kind, 0.969424_r_kind, 0.959808_r_kind, 0.958955_r_kind, &
          0.954316_r_kind, 0.980339_r_kind, 0.978795_r_kind/)
     
!    cp0 and dp0 for Oxygen optical thickness parameterization 
     cp0 = (/.969_r_kind, .969_r_kind, .974_r_kind, .986_r_kind,  &
          .986_r_kind, .988_r_kind, .988_r_kind/)
     dp0 = (/.00473_r_kind, .00415_r_kind, .0107_r_kind, .0217_r_kind, &
          .02612_r_kind, .01383_r_kind, .01947_r_kind/)


     alg1 = rmis; alg2 = rmis; alg3 = rmis 
     tbx(:) = rmis;  tby(:) = rmis
     
!    Mimic ssmis imager channels to corresponding ssmis channels

!    The coefficients (tbx) are derived from tb bias  
!    original env combination does not contan 91GHz, so nchanl=5 
     do i=1,5
        tbx(i) =  ap(i) + bp(i)*tb(i+11)
     end do

!    Coefficients for tbx to tby conversion 
     do i=1,5
        cp(i) = one/( cp0(i)*(one-dp0(i)) ) 
        dp(i) = cp(i) * dp0(i)
     end do
     
     tby(1)  =  cp(1)*tbx(1) - dp(1)*tbx(2);  
     tby(2)  =  cp(2)*tbx(2) - dp(2)*tbx(1);  
     tby(3)  =  cp(3)*tbx(3) - dp(3)*(.653_r_kind*tbx(2) + 96.6_r_kind);
     tby(4)  =  cp(4)*tbx(4) - dp(4)*tbx(5);  
     tby(5)  =  cp(5)*tbx(5) - dp(5)*tbx(4);  
!        tby(6)  =  cp(6)*tbx(6) - dp(6)*tbx(7);  
!        tby(7)  =  cp(7)*tbx(7) - dp(7)*tbx(6);  

!    Ice check
     call ice_check(tbx,seaice,ierr)
     if(ierr==3) return

!    Calculate parameter for clw
     tpw = 232.89_r_kind - 0.1486_r_kind*tby(1) - 0.3695_r_kind*tby(4)  & 
          - ( 1.8291_r_kind - 0.006193_r_kind*tby(3) )*tby(3)
     
     if( tbx(1)<r285 .and. tbx(3)<r285 ) then
        alg1 = -3.20_r_kind*(  &
             log( r290-tbx(1) ) - 2.80_r_kind - 0.42_r_kind*log( r290-tbx(3) )  )
     end if
     
     if( tbx(4)<r285 .and. tbx(3)<r285 ) then
        alg2 = -1.66_r_kind*(  &
             log( r290-tbx(4) ) - 2.90_r_kind - 0.340_r_kind*log( r290-tbx(3) )  );
     end if
     
     if( tbx(7)<r285 .and. tbx(3)<r285 ) then
        alg3 = -0.44_r_kind*( &
             log( r290-tbx(7) ) + 1.60_r_kind - 1.354_r_kind*log( r290-tbx(3) )  )
     end if

!    Determine clw
     if( alg1 > 0.70_r_kind ) then 
        clw = alg1
        iclwflg=1
     else
        if( alg2 > 0.28_r_kind ) then 
           clw = alg2
           iclwflg=2
        else
           if( tpw < 30.0_r_kind ) then 
              clw = alg3
              iclwflg=3
           else
              clw = alg2
              iclwflg=4
           end if
        end if
        
        if(clw>6.0_r_kind) clw = zero
     end if

  end if

  return
end subroutine ret_ssmis



subroutine ice_check(tbx,seaice,ierr)

! subprogram:    ice_check 
! prgmmr: weng, okamoto     org: np23                date: 2005-03-22
!
! abstract: using imager to estimate sea ice concentration 
! program history log:
!     2005-03-22  okamoto
!
! input argument list:
!     tbx      - coefficients for calculation of seaice 
! output argument list:
!     seaice     - sea ice concentration 
!     ierr    - error flag
!
! attributes:
!     language: f90
!     machine:  ibm RS/6000 SP
!
!$$$
  use kinds, only: r_kind, i_kind
  use constants, only: zero,one
  
  implicit none
  
  real(r_kind),dimension(7),intent(in):: tbx
  integer(i_kind),intent(out)         :: ierr
  real(r_kind),intent(out):: seaice
  
  ierr = zero 
  
  seaice = 91.9_r_kind - 2.994_r_kind*tbx(3) + 2.846_r_kind*tbx(1)  &
       - 0.386_r_kind*tbx(4) + 0.495_r_kind*tbx(6) + 1.005_r_kind*tbx(2) &
       - 0.904_r_kind*tbx(5)
  
  if( seaice>70.0_r_kind ) ierr = 3
  
  return
end subroutine ice_check
