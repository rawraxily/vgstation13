//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:33
var/global/list/rnd_machines = list()
//All devices that link into the R&D console fall into thise type for easy identification and some shared procs.
/obj/machinery/r_n_d
	name = "R&D Device"
	icon = 'icons/obj/machines/research.dmi'
	density = 1
	anchored = 1
	use_power = 1
	var/busy = 0
	var/hacked = 0
	var/disabled = 0
	var/shocked = 0
	var/obj/machinery/computer/rdconsole/linked_console
	var/obj/output
	var/stopped = 0
	var/base_state = ""
	var/build_time = 0

	machine_flags = SCREWTOGGLE | CROWDESTROY

	var/nano_file = ""

	var/max_material_storage = 0
	var/list/allowed_materials[0] //list of material IDs we take, if we whitelist

	var/research_flags //see setup.dm for details of these

	var/datum/wires/rnd/wires = null

/obj/machinery/r_n_d/New()
	rnd_machines |= src
	..()

	wires = new(src)

	base_state = icon_state
	icon_state_open = "[base_state]_t"

	if(research_flags & TAKESMATIN && !materials)
		materials = getFromDPool(/datum/materials, src)

	if(ticker) initialize()

// Define initial output.
/obj/machinery/r_n_d/initialize()
	..()
	output = src // broke protolathes you dummy
	if(research_flags &HASOUTPUT)
		for(var/direction in cardinal)
			var/O = locate(/obj/machinery/mineral/output, get_step(get_turf(src), direction))
			if(O)
				output=O
				break

/obj/machinery/r_n_d/Destroy()
	rnd_machines -= src
	wires = null
	..()

/obj/machinery/r_n_d/update_icon()
	overlays.len = 0
	if(linked_console)
		overlays += "[base_state]_link"

/obj/machinery/r_n_d/blob_act()
	if (prob(50))
		del(src)

/obj/machinery/r_n_d/attack_hand(mob/user as mob)
	if (shocked)
		shock(user,50)
	if(panel_open)
		wires.Interact(user)
	else if (research_flags & NANOTOUCH)
		ui_interact(user)
	return


/obj/machinery/r_n_d/Topic(href, href_list)
	if(..())
		return
	if(href_list["close"])
		if(usr.machine == src) usr.unset_machine()
		return 1
	usr.set_machine(src)
	src.add_fingerprint(usr)
	src.updateUsrDialog()

//Called when the hack wire is toggled in some way
/obj/machinery/r_n_d/proc/update_hacked()
	return

/obj/machinery/r_n_d/togglePanelOpen(var/item/toggleitem, mob/user)
	if(..())
		if (panel_open && linked_console)
			linked_console.linked_machines -= src
			switch(src.type)
				if(/obj/machinery/r_n_d/fabricator/protolathe)
					linked_console.linked_lathe = null
				if(/obj/machinery/r_n_d/destructive_analyzer)
					linked_console.linked_destroy = null
				if(/obj/machinery/r_n_d/fabricator/circuit_imprinter)
					linked_console.linked_imprinter = null
			linked_console = null
			overlays -= "[base_state]_link"
		return 1

/obj/machinery/r_n_d/crowbarDestroy(mob/user)
	if(..() == 1)
		if (materials)
			for(var/matID in materials.storage)
				var/datum/material/M = materials.getMaterial(matID)
				var/obj/item/stack/sheet/sheet = new M.sheettype(src.loc)
				if(sheet)
					var/available_num_sheets = round(materials.storage[matID]/sheet.perunit)
					if(available_num_sheets>0)
						sheet.amount = available_num_sheets
						materials.removeAmount(matID, sheet.amount * sheet.perunit)
					else
						qdel(sheet)
		return 1
	return -1

/obj/machinery/r_n_d/attackby(var/obj/item/O as obj, var/mob/user as mob)
	if (shocked)
		shock(user,50)
	if (busy)
		user << "<span class='warning'>The [src.name] is busy. Please wait for completion of previous operation.</span>"
		return 1
	if( ..() )
		return 1
	if(panel_open)
		wires.Interact(user)
		return 1
	if (stat)
		return 1
	if (disabled)
		return 1
	if (istype(O, /obj/item/device/multitool))
		if(!panel_open && research_flags &HASOUTPUT)
			var/result = input("Set your location as output?") in list("Yes","No","Machine Location")
			switch(result)
				if("Yes")
					var/found=0
					for(var/direction in cardinal)
						if(locate(user) in get_step(src,direction))
							found=1
					if(!found)
						user << "<span class='warning'>Cannot set this as the output location; You're too far away.</span>"
						return
					if(istype(output,/obj/machinery/mineral/output))
						del(output)
					output=new /obj/machinery/mineral/output(usr.loc)
					user << "<span class='notice'>Output set.</span>"
				if("No")
					return
				if("Machine Location")
					if(istype(output,/obj/machinery/mineral/output))
						del(output)
					output=src
					user << "<span class='notice'>Output set.</span>"
			return 1
		return
	if (!linked_console && !(istype(src, /obj/machinery/r_n_d/fabricator))) //fabricators get a free pass because they aren't tied to a console
		user << "\The [src.name] must be linked to an R&D console first!"
		return 1
	if(istype(O,/obj/item/stack/sheet) && research_flags &TAKESMATIN)
		busy = 1

		var/found = "" //the matID we're compatible with
		for(var/matID in materials.storage)
			var/datum/material/M = materials.getMaterial(matID)
			if(M.sheettype==O.type)
				found = matID
		if(!found)
			user << "<span class='warning'>\The [src.name] rejects \the [O.name].</span>"
			busy = 0
			return 1
		if(allowed_materials && allowed_materials.len)
			if(!(found in allowed_materials))
				user << "<span class='warning'>\The [src.name] rejects \the [O.name].</span>"
				busy = 0
				return 1

		var/obj/item/stack/sheet/S = O
		if (TotalMaterials() + S.perunit > max_material_storage)
			user << "<span class='warning'>\The [src.name]'s material bin is full. Please remove material before adding more.</span>"
			busy = 0
			return 1

		var/obj/item/stack/sheet/stack = O
		var/amount = round(input("How many sheets do you want to add? (0 - [stack.amount])") as num)//No decimals
		if(!O || !O.loc || O.loc != user)
			busy = 0
			return
		if(amount < 0)//No negative numbers
			amount = 0
		if(amount == 0)
			busy = 0
			return
		if(amount > stack.amount)
			amount = stack.amount
		if(max_material_storage - TotalMaterials() < (amount*stack.perunit))//Can't overfill
			amount = min(stack.amount, round((max_material_storage-TotalMaterials())/stack.perunit))

		if(research_flags & HASMAT_OVER)
			update_icon()
			overlays |= "[base_state]_[stack.name]"
			spawn(10)
				overlays -= "[base_state]_[stack.name]"

		icon_state = "[base_state]"
		use_power(max(1000, (3750*amount/10)))
		stack.use(amount)
		user << "<span class='notice'>You add [amount] sheets to the [src.name].</span>"
		icon_state = "[base_state]"

		var/datum/material/material = materials.getMaterial(found)
		materials.addAmount(found, amount * material.cc_per_sheet)
		busy = 0
		return 1
	src.updateUsrDialog()
	return 0

/obj/machinery/r_n_d/proc/TotalMaterials() //returns the total of all the stored materials. Makes code neater.
	if(materials)
		return materials.getVolume()
	return 0
