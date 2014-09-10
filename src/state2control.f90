subroutine state2control(rval,bval,grad)
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    state2control
!   prgmmr: tremolet
!
! abstract:  Converts variables from physical space to control space
!            This is also the adjoint of control2state
!
! program history log:
!   2007-04-16  tremolet - initial code
!   2008-11-28  todling  - update to GSI May 2008: add tsen and p3d
!   2009-01-15  todling  - handle predictors in quad precision
!   2009-04-21  derber   - modify call to getstvp to call to getuv
!   2009-06-15  parrish  - add call to strong_bk_ad when l_hyb_ens=.true. (hybrid ensemble run)
!   2009-08-12  lueken   - update documentation
!   2009-11-27  parrish  - for uv_hyb_ens=.true., then ensemble perturbations contain u,v instead of st,vp
!                            so introduce extra code to handle this case.
!   2010-02-20  parrish  - introduce modifications to allow dual resolution capability when running
!                            in hybrid ensemble mode.
!   2010-03-24  zhu      - use cstate for generalizing control variable
!   2010-04-29  todling  - update to use gsi_bundle; rename cstate to wbundle
!   2010-05-31  todling  - better consistency checks; add co/co2
!                        - ready to bypass analysis of (any) meteorological fields
!   2010-06-15  todling  - generalized handling of chemistry
!   2011-02-22  zhu      - add gust,vis,pblh
!   2011-05-15  auligne/todling - generalized cloud handling
!   2011-07-12  zhu      - add do_cw_to_hydro_ad and cw2hydro_ad
!   2011-11-01  eliu     - generalize the use of do_cw_to_hydro_ad
!   2012-02-08  kleist   - remove strong_bk_ad and ensemble_forward_model_ad and related parameters
!   2012-12-10  eliu     - add calls to linearized GFS moisture physics, normalized RH total, an                                 
!                          additional conversion of tsen to tv if linearized GFS moisture physics                           
!                          is turned on
!   2013-05-23  zhu      - add ntclen and predt for aircraft temperature bias correction
!   2013-10-25  todling  - nullify work pointers
!   2013-10-28  todling  - rename p3d to prse
!   2014-01-31  mkim     - add support for when ql and qi are CVs for all-sky mw radiance DA
!
!   input argument list:
!     rval - State variable
!     bval
!   output argument list:
!     grad - Control variable
!
!$$$
use kinds, only: i_kind,r_kind
use constants, only: zero
use control_vectors, only: control_vector
use control_vectors, only: cvars3d,cvars2d
use bias_predictors, only: predictors
use gsi_4dvar, only: nsubwin, lsqrtb
use gridmod, only: latlon1n,latlon11,regional,lat2,lon2,nsig
use jfunc, only: nsclen,npclen,ntclen
use jfunc, only: use_rhtot,do_gfsphys  
use cwhydromod, only: cw2hydro_ad
use gfs_moistphys_mod, only: moistphys_ad 
use normal_rhtot_mod, only: normal_rhtot_ad,cw2hydro_beta_ad   
use gsi_bundlemod, only: gsi_bundlecreate
use gsi_bundlemod, only: gsi_bundle
use gsi_bundlemod, only: gsi_bundlegetpointer
use gsi_bundlemod, only: gsi_bundlegetvar
use gsi_bundlemod, only: gsi_bundleputvar
use gsi_bundlemod, only: gsi_bundledestroy
use gsi_chemguess_mod, only: gsi_chemguess_get
use gsi_metguess_mod, only: gsi_metguess_get
use mpeu_util, only: getindex
use mpimod, only: mype 
use constants, only: max_varname_length

implicit none

! Declare passed variables
type(gsi_bundle)    , intent(inout) :: rval(nsubwin)
type(predictors)    , intent(in   ) :: bval
type(control_vector), intent(inout) :: grad

! Declare local variables
character(len=*),parameter::myname='state2control'
character(len=max_varname_length),allocatable,dimension(:) :: gases
character(len=max_varname_length),allocatable,dimension(:) :: clouds
integer(i_kind) :: ii,jj,i,j,k,ic,id,ngases,nclouds,istatus,istatus_oz,ierr 
type(gsi_bundle) :: wbundle ! work bundle

! Note: The following does not aim to get all variables in
!       the state and control vectors, but rather the ones
!       this routines knows how to handle.
integer(i_kind), parameter :: ncvars = 8
integer(i_kind) :: icps(ncvars)
integer(i_kind) :: icpblh,icgust,icvis,icoz
character(len=3), parameter :: mycvars(ncvars) = (/  &
                               'sf ', 'vp ', 'ps ', 't  ', 'q  ','cw ', 'ql ', 'qi '/)
logical :: pdf   
logical :: lc_sf,lc_vp,lc_ps,lc_t,lc_rh,lc_cw,lc_ql,lc_qi
real(r_kind),pointer,dimension(:,:)   :: cv_ps=>NULL()
real(r_kind),pointer,dimension(:,:)   :: cv_vis=>NULL()
real(r_kind),pointer,dimension(:,:,:) :: cv_sf=>NULL()
real(r_kind),pointer,dimension(:,:,:) :: cv_vp=>NULL()
real(r_kind),pointer,dimension(:,:,:) :: cv_t=>NULL()
real(r_kind),pointer,dimension(:,:,:) :: cv_rh=>NULL()
real(r_kind),pointer,dimension(:,:,:) :: cv_cw=>NULL() 

! Declare required local state variables
integer(i_kind), parameter :: nsvars = 7
integer(i_kind) :: isps(nsvars)
character(len=4), parameter :: mysvars(nsvars) = (/  &  ! vars from ST needed here
                               'u   ', 'v   ', 'prse', 'q   ', 'tsen', 'ql  ', 'qi  ' /)
logical :: ls_u,ls_v,ls_prse,ls_q,ls_tsen,ls_ql,ls_qi
real(r_kind),pointer,dimension(:,:)   :: rv_ps,rv_sst
real(r_kind),pointer,dimension(:,:)   :: rv_gust,rv_vis,rv_pblh
real(r_kind),pointer,dimension(:,:,:) :: rv_u,rv_v,rv_prse,rv_q,rv_tsen,rv_tv,rv_oz
real(r_kind),pointer,dimension(:,:,:) :: rv_ql,rv_qi  
real(r_kind),pointer,dimension(:,:,:) :: rv_rank3
real(r_kind),pointer,dimension(:,:)   :: rv_rank2
real(r_kind),pointer,dimension(:,:,:) :: rv_qc  

logical :: do_getuv,do_tv_to_tsen_ad,do_normal_rh_to_q_ad,do_getprs_ad,do_cw_to_hydro_ad
logical :: do_normal_rhtot_to_q_hydro_ad 
logical :: do_tsen_to_tv_ad !only involves this when turn do_gfsphys is true    

!******************************************************************************

if (lsqrtb) then
   write(6,*)trim(myname),': not for sqrt(B)'
   call stop2(311)
end if

! Inquire about clouds
call gsi_metguess_get ('clouds::3d',nclouds,istatus)
if (nclouds>0) then
   allocate(clouds(nclouds))
   call gsi_metguess_get ('clouds::3d',clouds,istatus)
endif

! Inquire about chemistry
call gsi_chemguess_get('dim',ngases,istatus)
if (ngases>0) then
    allocate(gases(ngases))
    call gsi_chemguess_get('gsinames',gases,istatus)
endif

! Since each internal vector [step(jj)] of grad has the same structure, pointers are
! the same independent of the subwindow jj
call gsi_bundlegetpointer (grad%step(1),mycvars,icps,istatus)
lc_sf =icps(1)>0;lc_vp =icps(2)>0;lc_ps=icps(3)>0;lc_t  =icps(4)>0
lc_rh =icps(5)>0;lc_cw =icps(6)>0;lc_ql=icps(7)>0;lc_qi =icps(8)>0

! Since each internal vector of xhat has the same structure, pointers are
! the same independent of the subwindow jj
call gsi_bundlegetpointer (rval(1),mysvars,isps,istatus)
ls_u  =isps(1)>0; ls_v   =isps(2)>0; ls_prse=isps(3)>0
ls_q  =isps(4)>0; ls_tsen=isps(5)>0; ls_ql =isps(6)>0; ls_qi =isps(7)>0

! Define what to do depending on what's in CV and SV
do_getuv            =lc_sf.and.lc_vp.and.ls_u  .and.ls_v
do_tv_to_tsen_ad    =lc_t .and.ls_q .and.ls_tsen
do_normal_rh_to_q_ad=lc_t .and.lc_rh.and.ls_prse.and.ls_q
do_getprs_ad        =lc_t .and.lc_ps.and.ls_prse
do_tsen_to_tv_ad    =(do_gfsphys .and. lc_cw) .or. (do_gfsphys .and. use_rhtot)

do_cw_to_hydro_ad=.false.
if (regional) then
   do_cw_to_hydro_ad=lc_cw.and.ls_ql.and.ls_qi
else
   do_cw_to_hydro_ad=lc_cw.and.ls_tsen.and.ls_ql.and.ls_qi.and.(.not.lc_ql) !ncep global
endif
do_normal_rhtot_to_q_hydro_ad=(lc_rh.and.lc_t.and.ls_prse).and.(.not.lc_cw).and. &            
                              (ls_q.and.ls_ql.and.ls_qi.and.ls_tsen).and.use_rhtot         

call gsi_bundlegetpointer (grad%step(1),'oz',icoz,istatus)
call gsi_bundlegetpointer (grad%step(1),'gust',icgust,istatus)
call gsi_bundlegetpointer (grad%step(1),'vis',icvis,istatus)
call gsi_bundlegetpointer (grad%step(1),'pblh',icpblh,istatus)


! Loop over control steps
do jj=1,nsubwin

!  Create a work bundle similar to grad control vector's bundle
   call gsi_bundlecreate ( wbundle, grad%step(jj), 'state2control work', istatus )
   if (istatus/=0) then
      write(6,*) trim(myname),': trouble creating work bundle'
      call stop2(999)
   endif

!  Get pointers to required control variables
   call gsi_bundlegetpointer (wbundle,'sf' ,cv_sf ,istatus)
   call gsi_bundlegetpointer (wbundle,'vp' ,cv_vp ,istatus)
   call gsi_bundlegetpointer (wbundle,'ps' ,cv_ps ,istatus)
   call gsi_bundlegetpointer (wbundle,'t'  ,cv_t,  istatus)
   call gsi_bundlegetpointer (wbundle,'q'  ,cv_rh ,istatus)
   if (icvis>0) call gsi_bundlegetpointer (wbundle,'vis'  ,cv_vis ,istatus)
   if (lc_cw) call gsi_bundlegetpointer (wbundle,'cw',cv_cw,istatus)    

!  Get pointers to this subwin require state variables
   call gsi_bundlegetpointer (rval(jj),'u'   ,rv_u,   istatus)
   call gsi_bundlegetpointer (rval(jj),'v'   ,rv_v,   istatus)
   call gsi_bundlegetpointer (rval(jj),'ps'  ,rv_ps,  istatus)
   call gsi_bundlegetpointer (rval(jj),'prse',rv_prse,istatus)
   call gsi_bundlegetpointer (rval(jj),'tv'  ,rv_tv,  istatus)
   call gsi_bundlegetpointer (rval(jj),'tsen',rv_tsen,istatus)
   call gsi_bundlegetpointer (rval(jj),'q'   ,rv_q ,  istatus)
!  call gsi_bundlegetpointer (rval(jj),'oz'  ,rv_oz , istatus)     
   call gsi_bundlegetpointer (rval(jj),'oz'  ,rv_oz , istatus_oz) 
   call gsi_bundlegetpointer (rval(jj),'sst' ,rv_sst, istatus)
   if (icgust>0) call gsi_bundlegetpointer (rval(jj),'gust' ,rv_gust, istatus)
   if (icvis >0) call gsi_bundlegetpointer (rval(jj),'vis'  ,rv_vis , istatus)
   if (icpblh>0) call gsi_bundlegetpointer (rval(jj),'pblh' ,rv_pblh, istatus)

   if (do_normal_rhtot_to_q_hydro_ad) then
      ierr=0
      if(ls_ql) call gsi_bundlegetpointer (rval(jj),'ql',rv_ql,istatus); ierr=ierr+istatus                            
      if(ls_qi) call gsi_bundlegetpointer (rval(jj),'qi',rv_qi,istatus); ierr=ierr+istatus                       
      if (ierr/=0) write(6,*)'state2control: can not get pointers for rv_ql &rv_qi'      
   endif

!  Adjoint of control to initial state
   call gsi_bundleputvar ( wbundle, 'sf',  zero,   istatus )
   call gsi_bundleputvar ( wbundle, 'vp',  zero,   istatus )
   if (do_tsen_to_tv_ad) then
      call gsi_bundleputvar ( wbundle, 't' ,  zero,  istatus )
   else
      call gsi_bundleputvar ( wbundle, 't' ,  rv_tv,  istatus )  
   endif
   call gsi_bundleputvar ( wbundle, 'q' ,  zero,   istatus )
   call gsi_bundleputvar ( wbundle, 'ps',  rv_ps,  istatus )
   if (icoz>0) then
      call gsi_bundleputvar ( wbundle, 'oz',  rv_oz,  istatus )
   else
      if(istatus_oz==0) rv_oz=zero 
   end if
   call gsi_bundleputvar ( wbundle, 'sst', rv_sst, istatus )
   if (icgust>0) call gsi_bundleputvar ( wbundle, 'gust', rv_gust, istatus )
   if (icvis >0) call gsi_bundleputvar ( wbundle, 'vis' , zero   , istatus )
   if (icpblh>0) call gsi_bundleputvar ( wbundle, 'pblh', rv_pblh, istatus )

   if (do_cw_to_hydro_ad) then
!     Case when cloud-vars do not map one-to-one
!     e.g. cw-to-ql&qi
      if(.not. do_tv_to_tsen_ad) allocate(rv_tsen(lat2,lon2,nsig))
      call cw2hydro_ad(rval(jj),wbundle,rv_tsen,clouds,nclouds)
      if(.not. do_tv_to_tsen_ad) then
         call tv_to_tsen_ad(cv_t,rv_q,rv_tsen)
         deallocate(rv_tsen)
      end if
   else
!     Case when cloud-vars map one-to-one, take care of them together
!     e.g. cw-to-cw
      do ic=1,nclouds
         id=getindex(cvars3d,clouds(ic))
         if (id>0) then
            call gsi_bundlegetpointer (rval(jj),clouds(ic),rv_rank3,istatus)
            call gsi_bundleputvar     (wbundle, clouds(ic),rv_rank3,istatus)
         endif
      enddo
   end if

!  Same one-to-one map for chemistry-vars; take care of them together
   do ic=1,ngases
      id=getindex(cvars3d,gases(ic))
      if (id>0) then
          call gsi_bundlegetpointer (rval(jj),gases(ic),rv_rank3,istatus)
          call gsi_bundleputvar     (wbundle, gases(ic),rv_rank3,istatus)
      endif
      id=getindex(cvars2d,gases(ic))
      if (id>0) then
          call gsi_bundlegetpointer (rval(jj),gases(ic),rv_rank2,istatus)
          call gsi_bundleputvar     (wbundle, gases(ic),rv_rank2,istatus)
      endif
   enddo

!  Adjoint of converting input normalized rhtot to q and hydrometeors
   if (do_normal_rhtot_to_q_hydro_ad) then
      pdf=.true.
      allocate(rv_qc(lat2,lon2,nsig))
      if (do_gfsphys) &
      call tsen_to_tv_ad(rv_tsen,rv_q,rv_tv)
      call cw2hydro_beta_ad(rv_qc,rv_tsen,rv_ql,rv_qi)
      if (do_tsen_to_tv_ad) &
      call moistphys_ad(rv_tsen,rv_q,rv_qc)
      call normal_rhtot_ad(cv_rh,cv_t,rv_prse,rv_q,rv_qc,rv_tsen,pdf)
      deallocate(rv_qc)
   else
      if (do_tsen_to_tv_ad .and. lc_cw) call tsen_to_tv_ad(rv_tsen,rv_q,rv_tv)
      if (do_gfsphys) call moistphys_ad(rv_tsen,rv_q,cv_cw)
   endif

!  Convert RHS calculations for u,v to st/vp for application of
!  background error
   if (do_getuv) call getuv(rv_u,rv_v,cv_sf,cv_vp,1)

!  Calculate sensible temperature
!  if(do_tv_to_tsen_ad) call tv_to_tsen_ad(cv_t,rv_q,rv_tsen)
   if(do_tv_to_tsen_ad .and. .not. do_normal_rhtot_to_q_hydro_ad ) call tv_to_tsen_ad(cv_t,rv_q,rv_tsen)                  

!  Adjoint of convert input normalized RH to q to add contribution of moisture
!  to t, p , and normalized rh
   if(do_normal_rh_to_q_ad) call normal_rh_to_q_ad(cv_rh,cv_t,rv_prse,rv_q)

!  Adjoint to convert ps to 3-d pressure
   if(do_getprs_ad) call getprs_ad(cv_ps,cv_t,rv_prse)

!  Adjoint of convert logvis to vis
   if(icvis >0) call logvis_to_vis_ad(cv_vis,rv_vis)

!  Adjoint of transfer variables

   do ii=1,wbundle%ndim
      grad%step(jj)%values(ii)=wbundle%values(ii)+grad%step(jj)%values(ii)
   enddo
   call gsi_bundledestroy(wbundle,istatus)
   if (istatus/=0) then
      write(6,*) trim(myname),': trouble destroying work bundle'
      call stop2(999)
   endif

end do

do ii=1,nsclen
  grad%predr(ii)=bval%predr(ii)
enddo
do ii=1,npclen
  grad%predp(ii)=bval%predp(ii)
enddo
if (ntclen>0) then 
   do ii=1,ntclen
     grad%predt(ii)=bval%predt(ii)
   enddo
end if

! Clean up
if (ngases>0) then
    deallocate(gases)
endif

if (nclouds>0) deallocate(clouds)

return
end subroutine state2control
