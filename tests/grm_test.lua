-- Import en lecture seule des associations main/rerolls depuis GRM.
local H = dofile((arg[0]:match("^(.*)[/\\][^/\\]+$") or ".") .. "/harness.lua")
local check = H.check

local c = H.NewClient("ImportGRM")
c.SetRoster({
  "Main-Hyjal", "Alt-Dalaran", "AltDeux-Ysondre", "Autre-Hyjal", "SansMain-Hyjal",
})
c.ns.ScanRoster()

check("GRM absent est detecte", not c.ns.IsGRMAvailable())
local unavailable, err = c.ns.BuildGRMImportPreview(c.g)
check("aucun import sans GRM", unavailable == nil and err == "unavailable")

c.ns.SetCharacterMain(c.g, "AltDeux", "Autre")
c.ns.SetCharacterMain(c.g, "Main", "Autre")
c.env.GRM = {
  GetPlayerMain = function(name)
    local mains = {
      ["Main-Hyjal"] = "Main-Hyjal",
      ["Alt-Dalaran"] = "Main-Hyjal",
      ["AltDeux-Ysondre"] = "Main-Hyjal",
      ["SansMain-Hyjal"] = "MainAbsent-KirinTor",
    }
    return mains[name] or ""
  end,
}

check("GRM est detecte", c.ns.IsGRMAvailable())
check("le nom complet inter-royaumes est conserve",
  c.g.members.Alt and c.g.members.Alt.fullName == "Alt-Dalaran")

local preview = c.ns.BuildGRMImportPreview(c.g)
check("un nouveau lien est trouve", preview.new == 1)
check("les liens en conflit sont signales", preview.changed == 2)
check("un main absent de GuildCotiz est ignore", preview.skipped == 1)
check("l'apercu ne modifie rien", c.ns.ResolveMain(c.g, "Alt") == "Alt"
  and c.ns.ResolveMain(c.g, "AltDeux") == "Autre")

local applied = c.ns.ApplyGRMImport(c.g, preview)
check("les trois changements sont importes", applied == 3)
check("le reroll inter-royaumes rejoint le main", c.ns.ResolveMain(c.g, "Alt") == "Main")
check("le conflit est remplace apres confirmation", c.ns.ResolveMain(c.g, "AltDeux") == "Main")
check("le main GRM n'est plus reroll", c.ns.ResolveMain(c.g, "Main") == "Main")

local second = c.ns.BuildGRMImportPreview(c.g)
check("un second import est idempotent", second.new == 0 and second.changed == 0
  and second.unchanged == 2 and c.ns.ApplyGRMImport(c.g, second) == 0)

os.exit(H.report())
