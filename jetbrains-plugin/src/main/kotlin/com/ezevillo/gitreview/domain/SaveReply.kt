package com.ezevillo.gitreview.domain

fun hasSaveState(output: String): Boolean = output.lineSequence().count { it == "capability\tsave-state" } == 1

data class SaveReply(val list: String, val config: String)
fun parseSaveReply(output: String): SaveReply? {
    val lines = output.replace("\r\n", "\n").split("\n").toMutableList()
    if (lines.lastOrNull() == "") lines.removeAt(lines.lastIndex)
    if (lines.size < 5 || lines.removeAt(0) != "save-state\t1" || lines.removeAt(0) != "status\t2" ||
        lines.removeAt(lines.lastIndex) != "save-state\tcomplete") return null
    val list = mutableListOf<String>()
    val config = mutableListOf<String>()
    for (line in lines) {
        if (line.startsWith("list\t") && config.isEmpty()) list += line.substring(5)
        else if (line.startsWith("config\t")) config += line.substring(7)
        else return null
    }
    if (list.none { Regex("branch\t[^\t]+\t1\t.*").matches(it) } ||
        config.count { it.startsWith("config\tremote\t") } != 1) return null
    return SaveReply(list.joinToString("\n", postfix = "\n"), config.joinToString("\n", postfix = "\n"))
}
