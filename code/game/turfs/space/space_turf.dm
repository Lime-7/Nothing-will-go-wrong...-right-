/turf/space
	icon = 'icons/turf/space.dmi'
	name = "\proper space"
	icon_state = "0"

	temperature = TCMB
	thermal_conductivity = OPEN_HEAT_TRANSFER_COEFFICIENT
	heat_capacity = HEAT_CAPACITY_VACUUM

	plane = PLANE_SPACE
	layer = SPACE_LAYER
	light_power = 0.25
	dynamic_lighting = DYNAMIC_LIGHTING_DISABLED
	intact = FALSE

	var/destination_z
	var/destination_x
	var/destination_y
	plane = PLANE_SPACE

/turf/space/Initialize(mapload)
	SHOULD_CALL_PARENT(FALSE)
	if(!istype(src, /turf/space/transit))
		icon_state = SPACE_ICON_STATE
	vis_contents.Cut() //removes inherited overlays

	if(initialized)
		stack_trace("Warning: [src]([type]) initialized multiple times!")
	initialized = TRUE

	if(length(smoothing_groups))
		sortTim(smoothing_groups) //In case it's not properly ordered, let's avoid duplicate entries with the same values.
		SET_BITFLAG_LIST(smoothing_groups)

	if(length(canSmoothWith))
		sortTim(canSmoothWith)
		if(canSmoothWith[length(canSmoothWith)] > MAX_S_TURF) //If the last element is higher than the maximum turf-only value, then it must scan turf contents for smoothing targets.
			smoothing_flags |= SMOOTH_OBJ
		SET_BITFLAG_LIST(canSmoothWith)

	var/area/A = loc
	if(!IS_DYNAMIC_LIGHTING(src) && IS_DYNAMIC_LIGHTING(A))
		add_overlay(/obj/effect/fullbright)

	if(light_power && light_range)
		update_light()

	if(opacity)
		has_opaque_atom = TRUE

	return INITIALIZE_HINT_NORMAL

/turf/space/BeforeChange()
	..()
	var/datum/space_level/S = GLOB.space_manager.get_zlev(z)
	S.remove_from_transit(src)
	if(light_sources) // Turn off starlight, if present
		set_light(0)

/turf/space/AfterChange(ignore_air, keep_cabling = FALSE)
	..()
	var/datum/space_level/S = GLOB.space_manager.get_zlev(z)
	S.add_to_transit(src)
	S.apply_transition(src)

/turf/space/proc/update_starlight()
	if(GLOB.configuration.general.starlight)
		for(var/t in RANGE_TURFS(1,src)) //RANGE_TURFS is in code\__HELPERS\game.dm
			if(isspaceturf(t))
				//let's NOT update this that much pls
				continue
			set_light(2)
			return
		set_light(0)

/turf/space/attackby(obj/item/C as obj, mob/user as mob, params)
	..()
	if(istype(C, /obj/item/stack/rods))
		var/obj/item/stack/rods/R = C
		var/obj/structure/lattice/L = locate(/obj/structure/lattice, src)
		var/obj/structure/lattice/catwalk/W = locate(/obj/structure/lattice/catwalk, src)
		if(W)
			to_chat(user, "<span class='warning'>There is already a catwalk here!</span>")
			return
		if(L)
			if(R.use(1))
				to_chat(user, "<span class='notice'>You construct a catwalk.</span>")
				playsound(src, 'sound/weapons/genhit.ogg', 50, 1)
				new/obj/structure/lattice/catwalk(src)
			else
				to_chat(user, "<span class='warning'>You need two rods to build a catwalk!</span>")
			return
		if(R.use(1))
			to_chat(user, "<span class='notice'>Constructing support lattice...</span>")
			playsound(src, 'sound/weapons/genhit.ogg', 50, 1)
			ReplaceWithLattice()
		else
			to_chat(user, "<span class='warning'>You need one rod to build a lattice.</span>")
		return

	if(istype(C, /obj/item/stack/tile/plasteel))
		var/obj/structure/lattice/L = locate(/obj/structure/lattice, src)
		if(L)
			var/obj/item/stack/tile/plasteel/S = C
			if(S.use(1))
				qdel(L)
				playsound(src, 'sound/weapons/genhit.ogg', 50, 1)
				to_chat(user, "<span class='notice'>You build a floor.</span>")
				ChangeTurf(/turf/simulated/floor/plating)
			else
				to_chat(user, "<span class='warning'>You need one floor tile to build a floor!</span>")
		else
			to_chat(user, "<span class='warning'>The plating is going to need some support! Place metal rods first.</span>")

/turf/space/Entered(atom/movable/A as mob|obj, atom/OL, ignoreRest = 0)
	..()
	if((!(A) || !(src in A.locs)))
		return

	if(destination_z && destination_x && destination_y && !A.pulledby && !HAS_TRAIT(A, TRAIT_CURRENTLY_Z_MOVING))
		var/tx = destination_x
		var/ty = destination_y
		var/turf/DT = locate(tx, ty, destination_z)
		var/itercount = 0
		while(DT.density || istype(DT.loc, /area/shuttle)) // Extend towards the center of the map, trying to look for a better place to arrive
			if(itercount++ >= 100)
				stack_trace("SPACE Z-TRANSIT ERROR: Could not find a safe place to land [A] within 100 iterations.")
				break
			if(tx < 128)
				tx++
			else
				tx--
			if(ty < 128)
				ty++
			else
				ty--
			DT = locate(tx, ty, destination_z)

		ADD_TRAIT(A, TRAIT_CURRENTLY_Z_MOVING, ROUNDSTART_TRAIT) // roundstart because its robust and won't be removed by someone being an idiot
		A.forceMove(DT)
		REMOVE_TRAIT(A, TRAIT_CURRENTLY_Z_MOVING, ROUNDSTART_TRAIT)

		itercount = 0
		var/atom/movable/current_pull = A.pulling
		while(current_pull)
			if(itercount > 100)
				stack_trace("SPACE Z-TRANSIT ERROR: [A] encountered a possible infinite loop while traveling through z-levels.")
				break
			var/turf/target_turf = get_step(current_pull.pulledby.loc, reverse_direction(current_pull.pulledby.dir)) || current_pull.pulledby.loc
			ADD_TRAIT(current_pull, TRAIT_CURRENTLY_Z_MOVING, ROUNDSTART_TRAIT)
			current_pull.forceMove(target_turf)
			REMOVE_TRAIT(current_pull, TRAIT_CURRENTLY_Z_MOVING, ROUNDSTART_TRAIT)
			current_pull = current_pull.pulling
			itercount++

/turf/space/proc/Sandbox_Spacemove(atom/movable/A as mob|obj)
	var/cur_x
	var/cur_y
	var/next_x
	var/next_y
	var/target_z
	var/list/y_arr

	if(src.x <= 1)
		if(istype(A, /obj/effect/meteor)||istype(A, /obj/effect/space_dust))
			qdel(A)
			return

		var/list/cur_pos = src.get_global_map_pos()
		if(!cur_pos) return
		cur_x = cur_pos["x"]
		cur_y = cur_pos["y"]
		next_x = (--cur_x||length(GLOB.global_map))
		y_arr = GLOB.global_map[next_x]
		target_z = y_arr[cur_y]
/*
		//debug
		to_chat(world, "Src.z = [src.z] in global map X = [cur_x], Y = [cur_y]")
		to_chat(world, "Target Z = [target_z]")
		to_chat(world, "Next X = [next_x]")
		//debug
*/
		if(target_z)
			A.z = target_z
			A.x = world.maxx - 2
			spawn (0)
				if(A && A.loc)
					A.loc.Entered(A)
	else if(src.x >= world.maxx)
		if(istype(A, /obj/effect/meteor))
			qdel(A)
			return

		var/list/cur_pos = src.get_global_map_pos()
		if(!cur_pos) return
		cur_x = cur_pos["x"]
		cur_y = cur_pos["y"]
		next_x = (++cur_x > length(GLOB.global_map) ? 1 : cur_x)
		y_arr = GLOB.global_map[next_x]
		target_z = y_arr[cur_y]
/*
		//debug
		to_chat(world, "Src.z = [src.z] in global map X = [cur_x], Y = [cur_y]")
		to_chat(world, "Target Z = [target_z]")
		to_chat(world, "Next X = [next_x]")
		//debug
*/
		if(target_z)
			A.z = target_z
			A.x = 3
			spawn (0)
				if(A && A.loc)
					A.loc.Entered(A)
	else if(src.y <= 1)
		if(istype(A, /obj/effect/meteor))
			qdel(A)
			return
		var/list/cur_pos = src.get_global_map_pos()
		if(!cur_pos) return
		cur_x = cur_pos["x"]
		cur_y = cur_pos["y"]
		y_arr = GLOB.global_map[cur_x]
		next_y = (--cur_y||length(y_arr))
		target_z = y_arr[next_y]
/*
		//debug
		to_chat(world, "Src.z = [src.z] in global map X = [cur_x], Y = [cur_y]")
		to_chat(world, "Next Y = [next_y]")
		to_chat(world, "Target Z = [target_z]")
		//debug
*/
		if(target_z)
			A.z = target_z
			A.y = world.maxy - 2
			spawn (0)
				if(A && A.loc)
					A.loc.Entered(A)

	else if(src.y >= world.maxy)
		if(istype(A, /obj/effect/meteor)||istype(A, /obj/effect/space_dust))
			qdel(A)
			return
		var/list/cur_pos = src.get_global_map_pos()
		if(!cur_pos) return
		cur_x = cur_pos["x"]
		cur_y = cur_pos["y"]
		y_arr = GLOB.global_map[cur_x]
		next_y = (++cur_y > length(y_arr) ? 1 : cur_y)
		target_z = y_arr[next_y]
/*
		//debug
		to_chat(world, "Src.z = [src.z] in global map X = [cur_x], Y = [cur_y]")
		to_chat(world, "Next Y = [next_y]")
		to_chat(world, "Target Z = [target_z]")
		//debug
*/
		if(target_z)
			A.z = target_z
			A.y = 3
			spawn (0)
				if(A && A.loc)
					A.loc.Entered(A)
	return

/turf/space/singularity_act()
	return

/turf/space/can_have_cabling()
	if(locate(/obj/structure/lattice/catwalk, src))
		return 1
	return 0

/turf/space/proc/set_transition_north(dest_z)
	destination_x = x
	destination_y = TRANSITION_BORDER_SOUTH + 1
	destination_z = dest_z

/turf/space/proc/set_transition_south(dest_z)
	destination_x = x
	destination_y = TRANSITION_BORDER_NORTH - 1
	destination_z = dest_z

/turf/space/proc/set_transition_east(dest_z)
	destination_x = TRANSITION_BORDER_WEST + 1
	destination_y = y
	destination_z = dest_z

/turf/space/proc/set_transition_west(dest_z)
	destination_x = TRANSITION_BORDER_EAST - 1
	destination_y = y
	destination_z = dest_z

/turf/space/proc/remove_transitions()
	destination_z = initial(destination_z)

/turf/space/attack_ghost(mob/dead/observer/user)
	if(destination_z)
		var/turf/T = locate(destination_x, destination_y, destination_z)
		user.forceMove(T)

/turf/space/acid_act(acidpwr, acid_volume)
	return 0

/turf/space/get_smooth_underlay_icon(mutable_appearance/underlay_appearance, turf/asking_turf, adjacency_dir)
	underlay_appearance.icon = 'icons/turf/space.dmi'
	underlay_appearance.icon_state = SPACE_ICON_STATE
	underlay_appearance.plane = PLANE_SPACE
	return TRUE
