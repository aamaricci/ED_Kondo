MODULE ED_CHI_SPIN_IMPURITIES
  USE SF_CONSTANTS, only:one,xi,zero,pi
  USE SF_TIMER  
  USE SF_IOTOOLS, only: str,reg,txtfy
  USE SF_LINALG,  only: inv,eigh,eye
  USE ED_INPUT_VARS
  USE ED_VARS_GLOBAL
  USE ED_EIGENSPACE
  USE ED_SETUP
  USE ED_SECTOR
  USE ED_HAMILTONIAN
  USE ED_AUX_FUNX
  implicit none
  private


  public :: build_chi_spin_impurities
  public :: eval_chi_spin_impurities

  integer                         :: istate,iorb,jorb,ispin
  integer                         :: isector
  complex(8),allocatable          :: vvinit(:)
  real(8),allocatable             :: alfa_(:),beta_(:)
  integer                         :: ipos,jpos
  integer                         :: i,j
  real(8)                         :: sgn,norm2
  real(8)                         :: state_e




contains


  !+------------------------------------------------------------------+
  !                            SPIN
  !PURPOSE  : Evaluate the Spin susceptibility \Chi_spin for a 
  ! single orbital: \chi = <S_a(\tau)S_a(0)>
  ! note: as S_a is hermitian particle and holes contributions
  ! are identical so work out only one lanczos tridiag. work out the 
  ! reduction for both values of isign in the same call.
  !+------------------------------------------------------------------+
  subroutine build_chi_spin_impurities()
    integer :: ispin,i,iimp
    integer :: iorb,jorb
    integer :: isite,jsite
    integer :: io,jo
    !
    if(.not.chispin_flag(Norb+1))return
    select case(ed_method)
    case ('lapack','full')
       return
    case default
       !Impurity GF
       do iimp=1,iNs
          if(Cindx(iimp)==0)cycle
          io = eNs+iimp
          if(MPIMASTER)write(LOGfile,"(A)")"Build spinChi:"//" imp "//str(iimp)
          if(MPIMASTER)call start_timer
          if(chispin_imp_flag(1))then
             call allocate_GFmatrix(SpinChiMatrix(io,io),Nstate=state_list%size)
             call lanc_build_spinChi_imp(iimp)
          endif
          if(chispin_imp_flag(2))then
             call allocate_GFmatrix(SpinChiMatrix(io,1),Nstate=state_list%size)
             call lanc_build_spinChi_all(iimp)
          endif
          if(chispin_imp_flag(3))then
             call allocate_GFmatrix(SpinChiMatrix(1,1),Nstate=state_list%size)
             call lanc_build_spinChi_imp_all(iimp)
          endif
          if(MPIMASTER)call stop_timer(unit=LOGfile)
       enddo
    end select
  end subroutine build_chi_spin_impurities


  subroutine eval_chi_spin_impurities()
    integer :: ispin,i,iimp
    integer :: iorb,jorb
    integer :: isite,jsite
    integer :: io,jo
    !
    if(.not.chispin_flag(Norb+1))return
    do iimp=1,iNs
       if(Cindx(iimp)==0)cycle
       if(MPIMASTER)write(LOGfile,"(A)")"Eval spinChi:"//" imp"//str(iimp)
       if(MPIMASTER)call start_timer
       select case(ed_method)
       case default
          io = eNs+iimp
          call lanc_eval_spinChi_impurity(io,io)
          ! call lanc_eval_spinChi_impurity(io,1)
          ! call lanc_eval_spinChi_impurity(1,1)
       case ('lapack','full')
          call full_eval_spinChi_impurity(io,io)
          ! call full_eval_spinChi_impurity(io,1)
          ! call full_eval_spinChi_impurity(1,1)
       end select
       if(MPIMASTER)call stop_timer(unit=LOGfile)
    enddo

    ! do iimp=1,iNs
    !    if(Cindx(iimp)==0)cycle
    !    io = eNs+iimp
    !    spinChi_w(io,1,:)   = 0.5d0*(spinChi_w(io,1,:) - spinChi_w(io,io,:) - spinChi_w(1,1,:))
    !    spinChi_tau(io,1,:) = 0.5d0*(spinChi_tau(io,1,:) - spinChi_tau(io,io,:) - spinChi_tau(1,1,:))
    !    spinChi_iv(io,1,:)  = 0.5d0*(spinChi_iv(io,1,:) - spinChi_iv(io,io,:) - spinChi_iv(1,1,:))
    !    spinChi_w(1,io,:)   = spinChi_w(io,1,:)
    !    spinChi_tau(1,io,:) = spinChi_tau(io,1,:)
    !    spinChi_iv(1,io,:)  = spinChi_iv(io,1,:)
    ! enddo
    !
  end subroutine eval_chi_spin_impurities




  !################################################################
  !################################################################
  !################################################################
  !################################################################




  subroutine lanc_build_spinChi_imp(iimp)
    integer,intent(in)                  :: iimp
    integer                             :: io,ipos
    real(8)                             :: Siorb,Sjorb
    type(sector)                        :: sectorI,sectorJ
    complex(8),dimension(:),allocatable :: state_cvec
    !
    io    = eNs + iimp
    !
    do istate=1,state_list%size
       !
       call allocate_GFmatrix(SpinChiMatrix(io,io),istate,Nchan=1)
       !
       isector    =  es_return_sector(state_list,istate)
       state_e    =  es_return_energy(state_list,istate)
#ifdef _MPI
       if(MpiStatus)then
          call es_return_cvector(MpiComm,state_list,istate,state_cvec) 
       else
          call es_return_cvector(state_list,istate,state_cvec) 
       endif
#else
       call es_return_cvector(state_list,istate,state_cvec)
#endif
       !
       !EVALUATE Sz_imp|gs>
       if(MpiMaster)then
          call build_sector(isector,sectorI)
          if(ed_verbose>=3)write(LOGfile,"(A,I6,2I4)")'Apply Sz_imp  :',isector,sectorI%Nups,sectorI%Ndws
          allocate(vvinit(sectorI%Dim)) ; vvinit=zero
          do i=1,sectorI%Dim
             call apply_op_Sz(i,sgn,io,sectorI)
             vvinit(i) = sgn*state_cvec(i)
          enddo
          call delete_sector(sectorI)
       else
          allocate(vvinit(1));vvinit=zero
       endif
       !      
       call tridiag_Hv_sector(isector,vvinit,alfa_,beta_,norm2)
       call add_to_lanczos_spinChi(norm2,state_e,alfa_,beta_,io,io,ichan=1,istate=istate)
       deallocate(alfa_,beta_)
       if(allocated(vvinit))deallocate(vvinit)
       !
       if(allocated(state_cvec))deallocate(state_cvec)
    enddo
    return
  end subroutine lanc_build_spinChi_imp



  subroutine lanc_build_spinChi_all(iimp)
    integer,intent(in)                  :: iimp
    integer                             :: io,ipos
    real(8)                             :: Siorb,Sjorb
    type(sector)                        :: sectorI,sectorJ
    complex(8),dimension(:),allocatable :: state_cvec
    !
    io    = eNs + iimp
    !
    do istate=1,state_list%size
       !
       call allocate_GFmatrix(SpinChiMatrix(1,1),istate,Nchan=1)
       !
       isector    =  es_return_sector(state_list,istate)
       state_e    =  es_return_energy(state_list,istate)
#ifdef _MPI
       if(MpiStatus)then
          call es_return_cvector(MpiComm,state_list,istate,state_cvec) 
       else
          call es_return_cvector(state_list,istate,state_cvec) 
       endif
#else
       call es_return_cvector(state_list,istate,state_cvec)
#endif
       !
       !
       !EVALUATE Sz_all|gs> 
       if(MpiMaster)then
          call build_sector(isector,sectorI)
          if(ed_verbose>=3)write(LOGfile,"(A,I6,2I4)")'Apply Sz_all:',isector,sectorI%Nups,sectorI%Ndws
          allocate(vvinit(sectorI%Dim)) ; vvinit=zero
          do i=1,sectorI%Dim
             call apply_op_Sz(i,sgn,[1,eNs],sectorI)
             vvinit(i) = sgn/eNs*state_cvec(i)
          enddo
          call delete_sector(sectorI)
       else
          allocate(vvinit(1));vvinit=zero
       endif
       !
       call tridiag_Hv_sector(isector,vvinit,alfa_,beta_,norm2)
       call add_to_lanczos_spinChi(norm2,state_e,alfa_,beta_,1,1,ichan=1,istate=istate)
       deallocate(alfa_,beta_)
       if(allocated(vvinit))deallocate(vvinit)
       !
       !
       if(allocated(state_cvec))deallocate(state_cvec)
    enddo
    return
  end subroutine lanc_build_spinChi_all




  subroutine lanc_build_spinChi_imp_all(iimp)
    integer,intent(in)                  :: iimp
    integer                             :: io,ipos
    real(8)                             :: Siorb,Sjorb
    type(sector)                        :: sectorI,sectorJ
    complex(8),dimension(:),allocatable :: state_cvec
    !
    io    = eNs + iimp
    !
    do istate=1,state_list%size
       !
       call allocate_GFmatrix(SpinChiMatrix(io,1),istate,Nchan=1)
       !
       isector    =  es_return_sector(state_list,istate)
       state_e    =  es_return_energy(state_list,istate)
#ifdef _MPI
       if(MpiStatus)then
          call es_return_cvector(MpiComm,state_list,istate,state_cvec) 
       else
          call es_return_cvector(state_list,istate,state_cvec) 
       endif
#else
       call es_return_cvector(state_list,istate,state_cvec)
#endif
       !       
       !
       !EVALUATE (Sz_imp + Sz_all)|gs> = Sz_imp|gs> + Sz_all|gs>
       if(MpiMaster)then
          call build_sector(isector,sectorI)
          if(ed_verbose>=3)write(LOGfile,"(A,I6,2I4)")'Apply (Sz_imp + Sz_all):',isector,sectorI%Nups,sectorI%Ndws
          allocate(vvinit(sectorI%Dim)) ; vvinit=zero
          do i=1,sectorI%Dim
             call apply_op_Sz(i,Siorb,io,sectorI)
             call apply_op_Sz(i,Sjorb,[1,eNs],sectorI)
             sgn       = Siorb + Sjorb/eNs
             vvinit(i) = sgn*state_cvec(i)
          enddo
          call delete_sector(sectorI)
       else
          allocate(vvinit(1));vvinit=zero
       endif
       !
       call tridiag_Hv_sector(isector,vvinit,alfa_,beta_,norm2)
       call add_to_lanczos_spinChi(norm2,state_e,alfa_,beta_,io,1,ichan=1,istate=istate)
       deallocate(alfa_,beta_)
       if(allocated(vvinit))deallocate(vvinit)
       !
       if(allocated(state_cvec))deallocate(state_cvec)
    enddo
    return
  end subroutine lanc_build_spinChi_imp_all


  !################################################################





  subroutine add_to_lanczos_spinChi(vnorm2,Ei,alanc,blanc,io,jo,ichan,istate)
    real(8)                                    :: vnorm2,Ei,Ej,Egs,pesoF,pesoAB,pesoBZ,de,peso,beta
    integer                                    :: nlanc
    real(8),dimension(:)                       :: alanc
    real(8),dimension(size(alanc))             :: blanc 
    integer                                    :: io,jo,ichan,istate
    real(8),dimension(size(alanc),size(alanc)) :: Z
    real(8),dimension(size(alanc))             :: diag,subdiag
    integer                                    :: i,j,ierr
    complex(8)                                 :: iw,chisp
    !
    Egs = state_list%emin       !get the gs energy
    !
    Nlanc = size(alanc)
    !
    pesoF  = vnorm2
    !
#ifdef _MPI
    if(MpiStatus)then
       call Bcast_MPI(MpiComm,alanc)
       call Bcast_MPI(MpiComm,blanc)
    endif
#endif
    diag(1:Nlanc)    = alanc(1:Nlanc)
    subdiag(2:Nlanc) = blanc(2:Nlanc)
    call eigh(diag(1:Nlanc),subdiag(2:Nlanc),Ev=Z(:Nlanc,:Nlanc))
    !
    call allocate_GFmatrix(SpinChiMatrix(io,jo),istate,ichan,Nlanc)
    !
    do j=1,nlanc
       Ej     = diag(j)
       dE     = Ej-Ei
       pesoAB = Z(1,j)*Z(1,j)
       peso   = pesoF*pesoAB
       !
       SpinChiMatrix(io,jo)%state(istate)%channel(ichan)%weight(j) = peso
       SpinChiMatrix(io,jo)%state(istate)%channel(ichan)%poles(j)  = de
    enddo
  end subroutine add_to_lanczos_spinChi








  !################################################################
  !################################################################
  !################################################################
  !################################################################








  subroutine lanc_eval_spinChi_impurity(io,jo)
    integer,intent(in)                  :: io,jo
    integer                             :: Nstates,istate
    integer                             :: Nchannels,ichan
    integer                             :: Nexcs,iexc,ii
    real(8)                             :: peso,de,pesoBZ,beta,Ei,Egs,dh,f,fp,sum
    real(8),dimension(Ns,Ns,0:Ltau)     :: spinChi_tau_tmp
    complex(8),dimension(Ns,Ns,Lreal)   :: spinChi_w_tmp
    complex(8),dimension(Ns,Ns,0:Lmats) :: spinChi_iv_tmp
    !
    !
    if(.not.allocated(SpinChiMatrix(io,jo)%state)) then
       print*, "CHI_SPIN WARNING: SpinChiMatrix%state not allocated. Nothing to do",io,jo
       return
    endif
    !
    beta= 1d0/temp
    Egs = state_list%emin
    pesoBZ = 1d0/zeta_function
    !
    !
    !this is the total number of available states  == state_list%size
    Nstates = size(SpinChiMatrix(io,jo)%state)
    call es_trim_size(state_list,temp,cutoff)
    do istate=1,state_list%trimd_size
       if(.not.allocated(SpinChiMatrix(io,jo)%state(istate)%channel))cycle
       Ei =  es_return_energy(state_list,istate)
       if(finiteT .AND. (beta*(Ei-Egs)>-log(1d-20)) )cycle
       if(finiteT)pesoBZ = exp(-beta*(Ei-Egs))/zeta_function
       Nchannels = size(SpinChiMatrix(io,jo)%state(istate)%channel)
       do ichan=1,Nchannels
          Nexcs  = size(SpinChiMatrix(io,jo)%state(istate)%channel(ichan)%poles)
          if(Nexcs==0)cycle
          do iexc=1,Nexcs
             peso  = SpinChiMatrix(io,jo)%state(istate)%channel(ichan)%weight(iexc)*pesoBZ
             dE    = SpinChiMatrix(io,jo)%state(istate)%channel(ichan)%poles(iexc)

             !Integrate:
             dh = beta/(Ltau-1)/2d0
             sum=0d0
             do i=0,Ltau-1
                j = i+1
                !
                if(i<Ltau/2)then
                   f = peso*exp(-tau(i)*dE)
                elseif(i>Ltau/2)then
                   f = peso*exp(-(beta-tau(i))*dE)
                else
                   f = peso*0.5d0*(exp(-tau(Ltau/2)*dE)+exp(-(beta-tau(Ltau/2))*dE))
                endif
                !
                !
                if(j<Ltau/2)then
                   fp = peso*exp(-tau(j)*dE)
                elseif(j>Ltau/2)then
                   fp = peso*exp(-(beta-tau(j))*dE)
                else
                   fp = peso*0.5d0*(exp(-tau(Ltau/2)*dE)+exp(-(beta-tau(Ltau/2))*dE))
                endif

                sum = sum+(fp+f)*dh
             enddo
             sum_spinChi(io,jo) = sum_spinChi(io,jo) + sum
             !
             !
             ! if(beta*dE > 1d-3)spinChi_iv(io,jo,0)=spinChi_iv(io,jo,0) + 2*peso*(1d0-exp(-beta*dE))/dE
             ! do i=1,Lmats
             !    spinChi_iv(io,jo,i)=spinChi_iv(io,jo,i) + peso*(1d0-exp(-beta*dE))*2d0*dE/(vm(i)**2+dE**2)
             ! enddo
             ! !
             ! !Symmetrize for low-T /large-beta, mostly occurring for zero T calculations
             ! do i=0,Ltau/2-1
             !    if(tau(i)*dE>-log(1d-20))cycle
             !    spinChi_tau(io,jo,i)=spinChi_tau(io,jo,i) + peso*exp(-tau(i)*dE)
             ! enddo
             ! spinChi_tau(io,jo,Ltau/2)=spinChi_tau(io,jo,Ltau/2) +&
             !      peso*0.5d0*(exp(-tau(Ltau/2)*dE)+exp(-(beta-tau(Ltau/2))*dE))
             ! do i=Ltau/2+1,Ltau
             !    if((beta-tau(i))*dE>-log(1d-20))cycle
             !    spinChi_tau(io,jo,i)=spinChi_tau(io,jo,i) + peso*exp(-(beta-tau(i))*dE)
             ! enddo
             ! !
             ! do i=1,Lreal
             !    spinChi_w(io,jo,i)=spinChi_w(io,jo,i) - &
             !         peso*(1d0-exp(-beta*dE))*( 1d0/(dcmplx(vr(i),eps) - dE) - 1d0/(dcmplx(vr(i),eps) + dE) )
             ! enddo
          enddo
       enddo
    enddo
    !
    return
  end subroutine lanc_eval_spinChi_impurity



  !############################################################################################
  !############################################################################################
  !############################################################################################
  !############################################################################################
  !############################################################################################
  !############################################################################################





  subroutine full_eval_spinChi_impurity(io,jo)
    integer      :: io,jo
    type(sector) :: sectorI,sectorJ
    integer      :: Nups(1)
    integer      :: Ndws(1)
    real(8)      :: Chio,Chjo,Sio,Sjo,Sje
    integer      :: i,j,ll,m,isector,ii
    integer      :: idim,ia
    real(8)      :: Ei,Ej,cc,peso,pesotot,beta
    real(8)      :: expterm,de,w0,it
    complex(8)   :: iw 
    !
    !
    !Spin susceptibility \X(tau). |<i|S_z|j>|^2
    !
    beta= 1d0/temp
    !
    do isector=1,Nsectors !loop over <i| total particle number
       call get_Nup(isector,nups)
       call get_Ndw(isector,ndws)
       if(ed_filling/=0 .AND. (sum(Nups)+sum(Ndws)/=ed_filling) )cycle
       if(SectorFlag    .AND. .not.(any(sector_list==isector)))cycle
       !
       call eta(isector,Nsectors,LOGfile)
       call build_sector(isector,sectorI)
       !
       do i=1,sectorI%Dim 
          do j=1,sectorI%Dim
             Chio=0d0
             Chjo=0d0
             expterm=exp(-beta*espace(isector)%e(i))+exp(-beta*espace(isector)%e(j))
             if(expterm<cutoff)cycle
             do ll=1,sectorI%Dim
                call apply_op_Sz(i,Sio,io,sectorI)
                Chio   = Chio + espace(isector)%M(ll,i)*Sio*conjg(espace(isector)%M(ll,j))
                call apply_op_Sz(i,Sjo,jo,sectorI)
                Chjo   = Chjo + espace(isector)%M(ll,i)*Sjo*conjg(espace(isector)%M(ll,j))
             enddo
             Ei=espace(isector)%e(i)
             Ej=espace(isector)%e(j)
             de=Ei-Ej
             do ii=1,2
                peso = Chio*Chjo/zeta_function
                !Matsubara (bosonic) frequency
                if(beta*dE > 1d-3)spinChi_iv(io,jo,0)=spinChi_iv(io,jo,0) + peso*2*exp(-beta*Ej)*(1d0-exp(-beta*dE))/dE
                do m=1,Lmats
                   spinChi_iv(io,jo,m)=spinChi_iv(io,jo,m)+ peso*exp(-beta*Ej)*2*dE/(vm(m)**2 + de**2)
                enddo
                !
                do m=0,Ltau 
                   it=tau(m)
                   spinChi_tau(io,jo,m)=spinChi_tau(io,jo,m) + exp(-it*Ei)*exp(-(beta-it)*Ej)*peso
                enddo
                !
                do m=1,Lreal
                   iw=dcmplx(vr(m),eps)
                   spinChi_w(io,jo,m)=spinChi_w(io,jo,m)-peso*(exp(-beta*Ei) - exp(-beta*Ej))/(iw+de)
                enddo
             enddo
             !
          enddo
       enddo
       call delete_sector(sectorI)
    enddo
  end subroutine full_eval_spinChi_impurity



END MODULE ED_CHI_SPIN_IMPURITIES
























