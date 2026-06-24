//
//  CountryFlags.swift
//  MenuScores
//
//  Maps national-team names / ESPN abbreviations to ISO 3166-1 flag codes so
//  soccer national teams (World Cup family) can render clean flags — the same
//  polished look the cricket badges already have — instead of generic crests.
//  Matching is EXACT (full name or known abbreviation) so club sides like
//  "America" or "Nacional" never accidentally resolve to a country flag.
//

import Foundation

enum CountryFlags {
    /// flagcdn subdivision codes are used for the UK home nations so England,
    /// Scotland and Wales get their own flags rather than the Union Jack.
    private static let map: [String: String] = {
        var m: [String: String] = [:]
        func add(_ code: String, _ names: [String]) {
            for n in names { m[n.lowercased()] = code }
        }
        // UEFA
        add("gb-eng", ["england", "eng"])
        add("gb-sct", ["scotland", "sco"])
        add("gb-wls", ["wales", "wal"])
        add("es", ["spain", "esp"])
        add("fr", ["france", "fra"])
        add("de", ["germany", "ger"])
        add("it", ["italy", "ita"])
        add("pt", ["portugal", "por"])
        add("nl", ["netherlands", "ned", "holland"])
        add("be", ["belgium", "bel"])
        add("hr", ["croatia", "cro"])
        add("rs", ["serbia", "srb"])
        add("ch", ["switzerland", "sui", "swi"])
        add("dk", ["denmark", "den"])
        add("pl", ["poland", "pol"])
        add("at", ["austria", "aut"])
        add("ua", ["ukraine", "ukr"])
        add("se", ["sweden", "swe"])
        add("no", ["norway", "nor"])
        add("tr", ["turkey", "türkiye", "turkiye", "tur"])
        add("cz", ["czechia", "czech republic", "cze"])
        add("hu", ["hungary", "hun"])
        add("gr", ["greece", "gre"])
        add("ie", ["ireland", "republic of ireland", "irl"])
        add("ro", ["romania", "rou"])
        add("sk", ["slovakia", "svk"])
        add("si", ["slovenia", "svn"])
        add("ru", ["russia", "rus"])
        // CONMEBOL
        add("br", ["brazil", "bra"])
        add("ar", ["argentina", "arg"])
        add("uy", ["uruguay", "uru"])
        add("co", ["colombia", "col"])
        add("cl", ["chile", "chi"])
        add("pe", ["peru", "per"])
        add("ec", ["ecuador", "ecu"])
        add("py", ["paraguay", "par"])
        add("bo", ["bolivia", "bol"])
        add("ve", ["venezuela", "ven"])
        // CONCACAF
        add("us", ["united states", "usa", "united states of america"])
        add("mx", ["mexico", "mex"])
        add("ca", ["canada", "can"])
        add("cr", ["costa rica", "crc"])
        add("pa", ["panama", "pan"])
        add("jm", ["jamaica", "jam"])
        add("hn", ["honduras", "hon"])
        add("cw", ["curacao", "curaçao", "cuw"])
        add("ht", ["haiti", "hai"])
        // CAF
        add("ma", ["morocco", "mar"])
        add("sn", ["senegal", "sen"])
        add("ci", ["ivory coast", "côte d'ivoire", "cote d'ivoire", "civ"])
        add("ng", ["nigeria", "nga"])
        add("gh", ["ghana", "gha"])
        add("cm", ["cameroon", "cmr"])
        add("eg", ["egypt", "egy"])
        add("dz", ["algeria", "alg"])
        add("tn", ["tunisia", "tun"])
        add("za", ["south africa", "rsa"])
        add("ml", ["mali", "mli"])
        add("cv", ["cape verde", "cabo verde", "cpv"])
        // AFC
        add("jp", ["japan", "jpn"])
        add("kr", ["south korea", "korea republic", "kor"])
        add("ir", ["iran", "irn"])
        add("sa", ["saudi arabia", "ksa"])
        add("au", ["australia", "aus"])
        add("qa", ["qatar", "qat"])
        add("iq", ["iraq", "irq"])
        add("ae", ["united arab emirates", "uae"])
        add("uz", ["uzbekistan", "uzb"])
        add("jo", ["jordan", "jor"])
        // OFC
        add("nz", ["new zealand", "nzl"])
        return m
    }()

    /// ISO/flagcdn code for a national team, or `nil` for clubs / unknowns.
    static func code(for teamName: String?) -> String? {
        guard let key = teamName?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return nil }
        return map[key]
    }

    /// A crisp flag URL (160px wide) for a national team, or `nil`.
    static func flagURL(for teamName: String?) -> URL? {
        guard let code = code(for: teamName) else { return nil }
        return URL(string: "https://flagcdn.com/w160/\(code).png")
    }
}
