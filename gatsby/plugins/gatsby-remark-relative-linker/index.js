const visit = require("unist-util-visit")

module.exports = ({ markdownAST }) => {
  visit(markdownAST, "link", node => {
    const { url } = node
    if (
      url &&
      !url.startsWith("//") &&
      !url.startsWith("http") &&
      url.startsWith("/")
    ) {
      node.url = url.replace(/(.*)\.md(#.*)?$/, (match, base, hash = '') => `${base}${hash}`)
    }
  })

  return markdownAST
}
