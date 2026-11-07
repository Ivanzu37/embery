import Testing
@testable import Embery

@Test func ocupaElGuionVacioDeLaPlantilla() {
    let diaria = "# Hoy\n\n## 📓 Registro\n- \n\n## 🔗 Relacionado\n- [[inicio]]"
    let r = Registro.insertar("- 10:30–11:20 · foco 50 min", en: diaria)
    #expect(r == "# Hoy\n\n## 📓 Registro\n- 10:30–11:20 · foco 50 min\n\n## 🔗 Relacionado\n- [[inicio]]")
}

@Test func vaDetrasDeLaUltimaLinea() {
    let diaria = "## 📓 Registro\n- a\n\n## Otra"
    #expect(Registro.insertar("- b", en: diaria) == "## 📓 Registro\n- a\n- b\n\n## Otra")
}

@Test func creaLaSeccionAntesDeRelacionado() {
    #expect(Registro.insertar("- b", en: "# Hoy\n## 🔗 Relacionado") == "# Hoy\n## 📓 Registro\n- b\n\n## 🔗 Relacionado")
}

@Test func subdominiosSiImitacionesNo() {
    let lista = [Bloqueado(nombre: "Instagram", web: "instagram.com")]
    #expect(webBloqueada("https://www.instagram.com/reels", lista) != nil)
    #expect(webBloqueada("https://m.instagram.com", lista) != nil)
    #expect(webBloqueada("https://notinstagram.com", lista) == nil)
}
