subroutine sub2grid(workin,t,p,q,oz,sst,slndt,sicet,cwmr,st,vp,iflg)
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    sub2grid adjoint of grid2sub
!   prgmmr: parrish          org: np22                date: 1994-02-12
!
! abstract: adjoint of horizontal grid to subdomain
!
! program history log:
!   2004-02-03  kleist, new mpi strategy
!   2004-05-06  derber 
!   2004-07-15  treadon - handle periodic subdomains
!   2004-07-28  treadon - add only on use declarations; add intent in/out
!   2004-10-26  kleist - remove u,v; do periodic update on st,vp
!   2004-03-30  treaon - change work1 dimension to max(iglobal,itotsub)
!
!   input argument list:
!     t        - t grid values                    
!     p        - p surface grid values                   
!     q        - q grid values                     
!     oz       - ozone grid values                            
!     sst      - sea surface temperature grid  
!     slndt    - land surface temperature 
!     sicet    - ice surface temperature                        
!     cwmr     - cloud water mixing ratio grid values                     
!     st       - streamfunction grid values                     
!     vp       - velocity potential grid values                     
!     iflg     = 1=not periodic, 2=periodic
!
!   output argument list:
!     workin   - output grid values on full grid after vertical operations
!
! attributes:
!   language: f90
!   machine:  ibm RS/6000 SP
!
!$$$
  use kinds, only: r_kind,i_kind
  use mpimod, only: irdsp_g,ircnt_g,iscnt_g,isdsp_g,&
       ierror,mpi_comm_world,mpi_rtype,&
       strip,strip_periodic,reorder
  use gridmod, only: itotsub,lat1,lon1,lat2,lon2,iglobal,&
       nlat,nlon,nsig,ltosi,ltosj,nsig1o,iglobal
  use jfunc, only: nsstsm,nozsm,nsltsm,ncwsm,nsitsm,nvpsm,nstsm,&
       npsm,nqsm,ntsm
  use constants, only: zero
  implicit none

! Declare passed variables
  integer(i_kind),intent(in):: iflg
  real(r_kind),dimension(lat2,lon2),intent(in):: p,sst,slndt,sicet
  real(r_kind),dimension(lat2,lon2,nsig),intent(in):: t,q,oz,cwmr,vp,st
  real(r_kind),dimension(nlat,nlon,nsig1o),intent(out):: workin

! Declare local variables
  integer(i_kind) i,j,k,l,ni1,ni2
  real(r_kind),dimension(lat1*lon1*(nsig*6+4)):: xhatsm
  real(r_kind),dimension(max(iglobal,itotsub),nsig1o):: work1  !  contain nsig1o slab of any variables

! Initialize variables
  do k=1,nsig1o
     do j=1,nlon
        do i=1,nlat
           workin(i,j,k)=zero
        end do
     end do
  end do
  do k=1,lat1*lon1*(nsig*6+4)
     xhatsm(k)=zero
  end do

! strip off boundary points and load vector for communication
  if (iflg==1) then
     call strip(st,xhatsm(nstsm),nsig)
     call strip(vp,xhatsm(nvpsm),nsig)
     call strip(p,xhatsm(npsm),1)
     call strip(t,xhatsm(ntsm),nsig)
     call strip(q,xhatsm(nqsm),nsig)
     call strip(oz,xhatsm(nozsm),nsig)
     call strip(sst,xhatsm(nsstsm),1)
     call strip(slndt,xhatsm(nsltsm),1)
     call strip(sicet,xhatsm(nsitsm),1)
     call strip(cwmr,xhatsm(ncwsm),nsig)
  elseif (iflg==2) then
     call strip_periodic(st,xhatsm(nstsm),nsig)
     call strip_periodic(vp,xhatsm(nvpsm),nsig)
     call strip_periodic(p,xhatsm(npsm),1)
     call strip_periodic(t,xhatsm(ntsm),nsig)
     call strip_periodic(q,xhatsm(nqsm),nsig)
     call strip_periodic(oz,xhatsm(nozsm),nsig)
     call strip_periodic(sst,xhatsm(nsstsm),1)
     call strip_periodic(slndt,xhatsm(nsltsm),1)
     call strip_periodic(sicet,xhatsm(nsitsm),1)
     call strip_periodic(cwmr,xhatsm(ncwsm),nsig)
  else
     write(6,*)'SUB2GRID:  ***ERROR*** iflg=',iflg,' is an illegal value'
  endif


! zero out work arrays
  do k=1,nsig1o
    do j=1,itotsub
      work1(j,k)=zero
    end do
  end do
! send subdomain vector to global slabs
  call mpi_alltoallv(xhatsm(1),iscnt_g,isdsp_g,&
       mpi_rtype,work1(1,1),ircnt_g,irdsp_g,mpi_rtype,&
       mpi_comm_world,ierror)

! reorder work1 array post communication
  call reorder(work1,nsig1o)
  do k=1,nsig1o
   do l=1,iglobal
      ni1=ltosi(l); ni2=ltosj(l)
      workin(ni1,ni2,k)=work1(l,k)
   end do
  end do

  return
end subroutine sub2grid
