module input_xml

  use constants
  use datatypes,       only: dict_create, dict_add_key, dict_has_key,          &
                             dict_get_key
  use error,           only: fatal_error
  use geometry_header, only: Cell, Surface, Lattice
  use global
  use output,          only: message
  use string,          only: lower_case, int_to_str

  implicit none

  type(DictionaryII), pointer :: &    ! used to count how many cells each
       & cells_in_univ_dict => null() ! universe contains

contains

!===============================================================================
! READ_INPUT_XML calls each of the separate subroutines for reading settings,
! geometry, materials, and tallies.
!===============================================================================

  subroutine read_input_xml()

    call read_settings_xml()
    call read_geometry_xml()
    call read_materials_xml()

  end subroutine read_input_xml

!===============================================================================
! READ_SETTINGS_XML reads data from a settings.xml file and parses it, checking
! for errors and placing properly-formatted data in the right data structures
!===============================================================================

  subroutine read_settings_xml()

    use xml_data_settings_t

    integer :: n
    integer :: coeffs_reqd
    character(MAX_WORD_LEN) :: type
    character(MAX_LINE_LEN) :: msg
    character(MAX_LINE_LEN) :: filename

    ! Display output message
    msg = "Reading settings XML file..."
    call message(msg, 5)

    ! Parse settings.xml file
    filename = trim(path_input) // "settings.xml"
    call read_xml_file_settings_t(filename)

    ! Cross-section library path
    path_xsdata = trim(xslibrary % path)

    ! Criticality information
    if (criticality % cycles > 0) then
       problem_type = PROB_CRITICALITY
       n_particles = criticality % particles
       n_cycles    = criticality % cycles
       n_inactive  = criticality % inactive
    end if

    ! Verbosity
    verbosity = verbosity_

    if (associated(source_ % coeffs)) then
       ! Determine external source type
       type = source_ % type
       call lower_case(type)
       select case (trim(type))
       case ('box')
          external_source % type = SRC_BOX
          coeffs_reqd = 6
       case default
          msg = "Invalid source type: " // trim(source_ % type)
          call fatal_error(msg)
       end select

       ! Coefficients for external surface
       n = size(source_ % coeffs)
       if (n < coeffs_reqd) then
          msg = "Not enough coefficients specified for external source."
          print *, n, coeffs_reqd
          call fatal_error(msg)
       elseif (n > coeffs_reqd) then
          msg = "Too many coefficients specified for external source."
          call fatal_error(msg)
       else
          allocate(external_source % values(n))
          external_source % values = source_ % coeffs
       end if
    end if

  end subroutine read_settings_xml

!===============================================================================
! READ_GEOMETRY_XML reads data from a geometry.xml file and parses it, checking
! for errors and placing properly-formatted data in the right data structures
!===============================================================================

  subroutine read_geometry_xml()

    use xml_data_geometry_t

    integer :: i, j, k
    integer :: n
    integer :: n_x, n_y
    integer :: universe_num
    integer :: count
    integer :: coeffs_reqd
    character(MAX_LINE_LEN) :: filename
    character(MAX_LINE_LEN) :: msg
    character(MAX_WORD_LEN) :: word
    type(Cell),    pointer :: c => null()
    type(Surface), pointer :: s => null()
    type(Lattice), pointer :: l => null()

    ! Display output message
    msg = "Reading geometry XML file..."
    call message(msg, 5)

    ! ==========================================================================
    ! READ CELLS FROM GEOMETRY.XML

    ! Parse geometry.xml file
    filename = trim(path_input) // "geometry.xml"
    call read_xml_file_geometry_t(filename)

    ! Allocate cells array
    n_cells = size(cell_)
    allocate(cells(n_cells))

    n_universes = 0
    do i = 1, n_cells
       c => cells(i)
       
       ! Copy data into cells
       c % uid      = cell_(i) % uid
       c % universe = cell_(i) % universe
       c % material = cell_(i) % material
       c % fill     = cell_(i) % fill

       ! Check to make sure that either material or fill was specified
       if (c % material == 0 .and. c % fill == 0) then
          msg = "Neither material nor fill was specified for cell " // & 
               trim(int_to_str(c % uid))
          call fatal_error(msg)
       end if

       ! Check to make sure that both material and fill haven't been
       ! specified simultaneously
       if (c % material /= 0 .and. c % fill /= 0) then
          msg = "Cannot specify material and fill simultaneously"
          call fatal_error(msg)
       end if

       ! Check to make sure that surfaces were specified
       if (.not. associated(cell_(i) % surfaces)) then
          msg = "No surfaces specified for cell " // trim(int_to_str(c % uid))
          call fatal_error(msg)
       end if

       ! Allocate array for surfaces and copy
       n = size(cell_(i) % surfaces)
       c % n_surfaces = n
       allocate(c % surfaces(n))
       c % surfaces = cell_(i) % surfaces

       ! Add cell to dictionary
       call dict_add_key(cell_dict, c % uid, i)

       ! For cells, we also need to check if there's a new universe --
       ! also for every cell add 1 to the count of cells for the
       ! specified universe
       universe_num = cell_(i) % universe
       if (.not. dict_has_key(cells_in_univ_dict, universe_num)) then
          n_universes = n_universes + 1
          count = 1
          call dict_add_key(universe_dict, universe_num, n_universes)
       else
          count = 1 + dict_get_key(cells_in_univ_dict, universe_num)
       end if
       call dict_add_key(cells_in_univ_dict, universe_num, count)

    end do

    ! ==========================================================================
    ! READ SURFACES FROM GEOMETRY.XML

    ! Allocate cells array
    n_surfaces = size(surface_)
    allocate(surfaces(n_surfaces))

    do i = 1, n_surfaces
       s => surfaces(i)
       
       ! Copy data into cells
       s % uid = surface_(i) % uid

       ! Copy and interpret surface type
       word = surface_(i) % type
       call lower_case(word)
       select case(trim(word))
       case ('x-plane')
          s % type = SURF_PX
          coeffs_reqd  = 1
       case ('y-plane')
          s % type = SURF_PY
          coeffs_reqd  = 1
       case ('z-plane')
          s % type = SURF_PZ
          coeffs_reqd  = 1
       case ('plane')
          s % type = SURF_PLANE
          coeffs_reqd  = 4
       case ('x-cylinder')
          s % type = SURF_CYL_X
          coeffs_reqd  = 3
       case ('y-cylinder')
          s % type = SURF_CYL_Y
          coeffs_reqd  = 3
       case ('z-cylinder')
          s % type = SURF_CYL_Z
          coeffs_reqd  = 3
       case ('sphere')
          s % type = SURF_SPHERE
          coeffs_reqd  = 4
       case ('box-x')
          s % type = SURF_BOX_X
          coeffs_reqd  = 4
       case ('box-y')
          s % type = SURF_BOX_Y
          coeffs_reqd  = 4
       case ('box-z')
          s % type = SURF_BOX_Z
          coeffs_reqd  = 4
       case ('box') 
          s % type = SURF_BOX
          coeffs_reqd  = 6
       case ('quadratic')
          s % type = SURF_GQ
          coeffs_reqd  = 10
       case default
          msg = "Invalid surface type: " // trim(surface_(i) % type)
          call fatal_error(msg)
       end select

       ! Check to make sure that the proper number of coefficients
       ! have been specified for the given type of surface. Then copy
       ! surface coordinates.

       n = size(surface_(i) % coeffs)
       if (n < coeffs_reqd) then
          msg = "Not enough coefficients specified for surface: " // & 
               trim(int_to_str(s % uid))
          print *, n, coeffs_reqd
          call fatal_error(msg)
       elseif (n > coeffs_reqd) then
          msg = "Too many coefficients specified for surface: " // &
               trim(int_to_str(s % uid))
          call fatal_error(msg)
       else
          allocate(s % coeffs(n))
          s % coeffs = surface_(i) % coeffs
       end if

       ! Boundary conditions
       word = surface_(i) % boundary
       call lower_case(word)
       select case (trim(word))
       case ('transmission', 'transmit', '')
          s % bc = BC_TRANSMIT
       case ('vacuum')
          s % bc = BC_VACUUM
       case ('reflective', 'reflect', 'reflecting')
          s % bc = BC_REFLECT
       case ('periodic')
          s % bc = BC_PERIODIC
       case default
          msg = "Unknown boundary condition '" // trim(word) // &
               "' specified on surface " // trim(int_to_str(s % uid))
          call fatal_error(msg)
       end select

       ! Add surface to dictionary
       call dict_add_key(surface_dict, s % uid, i)

    end do

    ! ==========================================================================
    ! READ LATTICES FROM GEOMETRY.XML

    ! Allocate lattices array
    n_lattices = size(lattice_)
    allocate(lattices(n_lattices))

    do i = 1, n_lattices
       l => lattices(i)

       ! UID of lattice
       l % uid = lattice_(i) % uid

       ! Read lattice type
       word = lattice_(i) % type
       call lower_case(word)
       select case (trim(word))
       case ('rect', 'rectangle', 'rectangular')
          l % type = LATTICE_RECT
       case ('hex', 'hexagon', 'hexagonal')
          l % type = LATTICE_HEX
       case default
          msg = "Invalid lattice type: " // trim(lattice_(i) % type)
          call fatal_error(msg)
       end select

       ! Read number of lattice cells in each dimension
       n = size(lattice_(i) % dimension)
       if (n /= 2 .and. n /= 3) then
          msg = "Lattice must be two or three dimensions."
          call fatal_error(msg)
       end if
       n_x = lattice_(i) % dimension(1)
       n_y = lattice_(i) % dimension(2)
       l % n_x = n_x
       l % n_y = n_y

       ! Read lattice origin location
       if (size(lattice_(i) % dimension) /= size(lattice_(i) % origin)) then
          msg = "Number of entries on <origin> must be the same as the " // &
               "number of entries on <dimension>."
          call fatal_error(msg)
       end if
       l % x0 = lattice_(i) % origin(1)
       l % y0 = lattice_(i) % origin(2)

       ! Read lattice widths
       if (size(lattice_(i) % width) /= size(lattice_(i) % origin)) then
          msg = "Number of entries on <width> must be the same as the " // &
               "number of entries on <origin>."
          call fatal_error(msg)
       end if
       l % width_x = lattice_(i) % width(1)
       l % width_y = lattice_(i) % width(2)

       ! Read universes
       allocate(l % element(n_x, n_y))
       do k = 0, n_y - 1
          do j = 1, n_x
             l % element(j, n_y - k) = lattice_(i) % universes(j + k*n_x)
          end do
       end do

       ! Add lattice to dictionary
       call dict_add_key(lattice_dict, l % uid, i)

    end do

  end subroutine read_geometry_xml

!===============================================================================
! READ_MATERIAL_XML reads data from a materials.xml file and parses it, checking
! for errors and placing properly-formatted data in the right data structures
!===============================================================================

  subroutine read_materials_xml

    use xml_data_materials_t

    integer :: i, j
    integer :: n
    real(8) :: val
    character(MAX_WORD_LEN) :: units
    character(MAX_WORD_LEN) :: name
    character(MAX_LINE_LEN) :: filename
    character(MAX_LINE_LEN) :: msg
    type(Material),    pointer :: m => null()
    type(nuclide_xml), pointer :: nuc => null()

    ! Display output message
    msg = "Reading materials XML file..."
    call message(msg, 5)

    ! Parse materials.xml file
    filename = trim(path_input) // "materials.xml"
    call read_xml_file_materials_t(filename)

    ! Allocate cells array
    n_materials = size(material_)
    allocate(materials(n_materials))

    do i = 1, n_materials
       m => materials(i)

       ! Copy material uid
       m % uid = material_(i) % uid

       ! Copy density -- the default value for the units is given in the
       ! material_t.xml file and doesn't need to be specified here, hence case
       ! default results in an error.
       val   = material_(i) % density % value
       units = material_(i) % density % units
       call lower_case(units)
       select case(trim(units))
       case ('g/cc', 'g/cm3')
          m % atom_density = -val
       case ('kg/m3')
          m % atom_density = -0.001 * val
       case ('atom/b-cm')
          m % atom_density = val
       case ('atom/cm3', 'atom/cc')
          m % atom_density = 1.0e-24 * val
       case default
          msg = "Unkwown units '" // trim(material_(i) % density % units) // &
               "' specified on material " // trim(int_to_str(m % uid))
          call fatal_error(msg)
       end select
       
       ! Check to ensure material has at least one nuclide
       if (.not. associated(material_(i) % nuclides)) then
          msg = "No nuclides specified on material " // trim(int_to_str(m % uid))
          call fatal_error(msg)
       end if

       ! allocate arrays in Material object
       n = size(material_(i) % nuclides)
       m % n_nuclides = n
       allocate(m % names(n))
       allocate(m % nuclide(n))
       allocate(m % xsdata(n))
       allocate(m % atom_percent(n))

       do j = 1, n
          ! Combine nuclide identifier and cross section and copy into names
          nuc => material_(i) % nuclides(j)
          name = trim(nuc % name) // "." // trim(nuc % xs)
          m % names(j) = name

          ! Check if no atom/weight percents were specified or if both atom and
          ! weight percents were specified
          if (nuc % ao == ZERO .and. nuc % wo == ZERO) then
             msg = "No atom or weight percent specified for nuclide " // &
                  trim(name)
             call fatal_error(msg)
          elseif (nuc % ao /= ZERO .and. nuc % wo /= ZERO) then
             msg = "Cannot specify both atom and weight percents for a nuclide: " &
                  // trim(name)
          end if

          ! Copy atom/weight percents
          if (nuc % ao /= ZERO) then
             m % atom_percent(j) = nuc % ao
          else
             m % atom_percent(j) = -nuc % wo
          end if
       end do

       ! Add material to dictionary
       call dict_add_key(material_dict, m % uid, i)

    end do

  end subroutine read_materials_xml

!===============================================================================
! READ_TALLIES_XML reads data from a tallies.xml file and parses it, checking
! for errors and placing properly-formatted data in the right data structures
!===============================================================================

  subroutine read_tallies_xml

    use xml_data_tallies_t

    integer :: i
    character(MAX_LINE_LEN) :: filename
    character(MAX_LINE_LEN) :: msg
    type(Tally),    pointer :: t => null()

    ! Display output message
    msg = "Reading tallies XML file..."
    call message(msg, 5)

    ! Parse tallies.xml file
    filename = trim(path_input) // "tallies.xml"
    call read_xml_file_tallies_t(filename)

    ! Allocate cells array
    n_tallies = size(tally_)
    allocate(tallies(n_tallies))

    do i = 1, n_tallies
       t => tallies(i)

       ! Copy material uid
       t % uid = tally_(i) % id

    end do

  end subroutine read_tallies_xml

end module input_xml