module OCEAN_rixs_holder
  use AI_kinds
  implicit none

  private

  complex(DP), allocatable :: xes_vec(:,:,:,:)

  integer :: zee
  integer :: ell
  logical :: is_init
  logical :: have_cksv

  public :: OCEAN_rixs_holder_load, OCEAN_rixs_holder_clean

  contains

  subroutine OCEAN_rixs_holder_clean
    implicit none

    if( is_init ) deallocate( xes_vec )
    is_init = .false.
    have_cksv = .false.
  end subroutine OCEAN_rixs_holder_clean

  subroutine OCEAN_rixs_holder_init( sys, ierr )
    use OCEAN_system
    use OCEAN_mpi, only : myid, root
    implicit none
    type(O_system), intent( in ) :: sys
    integer, intent( inout ) :: ierr

    ! run in serial !
    if( myid .ne. root ) return

    ! Check to see if we are still ok
    !   if previously initiated and both Z and L are the same
    if( is_init ) then
      if( zee .eq. sys%ZNL(1) .and. ell .eq. sys%ZNL(2) ) return
      deallocate( cksv )
      is_init = .false.
      is_loaded = .false.
    endif

    allocate( xes_vec( sys%val_bands, sys%nkpts, 2 * sys%ZNL(2) + 1, sys%nedges )

  end subroutine OCEAN_rixs_holder_init

  subroutine OCEAN_rixs_holder_load( sys, psi, file_selector, ierr )
    use OCEAN_system
    use OCEAN_psi
    use OCEAN_mpi, only : myid, root, comm

    implicit none
    
    type(O_system), intent( in ) :: sys 
    type(OCEAN_vector), intent( inout ) :: psi
    integer, intent( in ) :: file_selector
    integer, intent( inout ) :: ierr

    call OCEAN_rixs_holder_init( sys, ierr )
    if( ierr .ne. 0 ) return


    if( myid .eq. root ) then

      if( have_cksv .eq. .false. ) then
        call cksv_read( sys, file_selector, ierr )
        if( ierr. ne. 0 ) return
      endif

      call rixs_seed( sys, psi, file_selector, ierr )
      
    endif

#ifdef MPI
    call MPI_BCAST( psi%valr, psi%val_full_size, MPI_DOUBLE_PRECISION, root, comm, ierr )
    if( ierr .ne. MPI_SUCCESS ) return

    call MPI_BCAST( pis%vali, psi%val_full_size, MPI_DOUBLE_PRECISION, root, comm, ierr )
    if( ierr .ne. MPI_SUCCESS ) return
#endif


  end subroutine OCEAN_rixs_holder_load


  subroutine rixs_seed( sys, psi, file_selector, ierr )
    use OCEAN_system
    use OCEAN_psi

    implicit none

    type(O_system), intent( in ) :: sys 
    type(OCEAN_vector), intent( inout ) :: psi
    integer, intent( in ) :: file_selector
    integer, intent( inout ) :: ierr
    !
    complex(DP), allocatable :: rex( :, :, :, : ), tmp_psi( :, :, :, : )
    integer :: edge_iter, ic, icms, icml, ivms, ispin, i, j
    character(len=11) :: echamp_file

    allocate( rex( sys%numbands, sys%nkpts, 4*(2*ZNL(2)+1), sys%nedges ), &
              tmp_psi( sys%val_bands, sys%numbands, sys%nkpts, sys%nspn**2 ) )

    do edge_iter = 1, sys%nedges
      write(6,'(A7,I4.4)') 'echamp.', edge_iter
      write(echamp_file, '(A7,I4.4)') 'echamp.', edge_iter
      open(unit=99,file=echamp_file,form='unformatted',status='old')
      rewind(99)
      read(99) rex
      close(99)


! JTV block this so psi is in cache
      ic = 0
      do icms = 0, 1
        do icml = 1, sys%ZNL(2)*2 + 1
          do ivms = 1, 3, 2
            ispin = min( icms + ivms, sys%nspn**2 )
            ic = ic + 1
            do i = 1, sys%val_bands
              do j = 1, sys%numbands
                tmp_psi( j, i, ik, ispin ) = tmp_psi( j, i, ik, ispin ) + &
                    rex( j, ik, ic, edge_iter ) * xes_vec(i,ik,icml,edge_iter)
              enddo
            enddo
          enddo
        enddo
      enddo
    enddo    

    psi%valr(:,:,:,:) = real( tmp_psi(:,:,:,:) )
    psi%vali(:,:,:,:) = aimag( tmp_psi(:,:,:,:) )

    deallocate( rex )

  end subroutine


  subroutine cksv_read( sys, file_selector, ierr )
    use OCEAN_system
    implicit none
    type(O_system), intent( in ) :: sys
    integer, intent( in ) :: file_selector
    integer, intent( inout ) :: ierr

    real(DP), allocatable :: mer, mei, pcr, pci
    real(DP) :: rr, ri, ir, ii
    integer :: nptot, ntot, nptot_check
    integer :: icml, iter, ik, i, edge_iter


    select case ( file_selector )

    case( 1 )
      
      do edge_iter = 1, sys%nedges
        write(6,'(A5,A2,I4.4)' ) 'cksv.', sys%elname, edge_iter
        write(cks_filename,'(A5,A2,I4.4)' ) 'cksv.', sys%elname, edge_iter
        open(unit=99,file=cks_filename,form='unformatted',status='old')
        rewind( 99 )
        read ( 99 ) nptot, ntot
        read ( 99 ) tau( : )
        write(6,*) tau(:)
        if( edge_iter .eq. 1 ) allocate( pcr( nptot, ntot ), pci( nptot, ntot ) )
        read ( 99 ) pcr
        read ( 99 ) pci
        close( unit=99 )

        ! check ntot
        if( ntot .ne. sys%nkpts * sys%val_bands ) then
          write(6,*) 'Mismatch bands*kpts vs ntot'
          ierr = -1
          return
        endif

        if( edge_iter .eq. 1 ) then
          allocate( mer( nptot, -sys%ZNL(2) : sys%ZNL(2) ),  mei( nptot, -sys%(ZNL(2) : sys%ZNL(2) ) )

          write(mel_filename,'(A5,A1,I3.3,A1,I2.2,A1,I2.2,A1,I2.2)' ) 'mels.', 'z', sys%ZNL(1), & 
              'n', sys%ZNL(2), 'l', sys%ZNL(3), 'p', 1 
           open( unit=99, file=mel_filename, form='formatted', status='old' ) 
          rewind( 99 ) 
          do icml = -sys%ZNL(3), sys%ZNL(3)
            do iter = 1, nptot
              read( 99, * ) mer( iter, icml ), mei( iter, icml ) 
            enddo
          enddo
          close( 99 ) 
          nptot_check = nptot

        else
          if( nptot .ne. nptot_check ) then
            write(6,*) 'nptot inconsistent between cores'
            ierr = -1
            return
          endif
        endif
    

        do icml = -sys%ZNL(3), sys%ZNL(3)
          iter = 0
          do ik = 1, sys%nkpts
            do i = 1, sys%val_bands
              iter = iter + 1
              rr = dot_product( mer( :, icml ), pcr( :, iter ) )
              ri = dot_product( mer( :, icml ), pci( :, iter ) )
              ir = dot_product( mei( :, icml ), pcr( :, iter ) )
              ii = dot_product( mei( :, icml ), pci( :, iter ) )
              xes_vec(i,ik,1 + icml + sys%lc, edge_iter) = cmplx( rr - ii, ri + ir )
            enddo
          enddo
        enddo
      enddo

      deallocate( mer, mei, pcr, pci )

      have_cksv = .true.


    case( 0 )
      write(6,*) 'John is lazy'
      ierr = -1
      return
    case default
      ierr = -1
      return
    end select

  end subroutine cksv_read


end module OCEAN_rixs_holder
