import * as React from "react"
import { Link, useI18next } from "gatsby-plugin-react-i18next"

const Layout = ({ location, title, children }) => {
  const rootPath = `${__PATH_PREFIX__}/`
  const isRootPath = location.pathname === rootPath
  const { languages, originalPath } = useI18next()
  const LanguageElem = (
    <ul className="languages">
      {languages.map(lng => (
        <li key={lng}>
          <Link to={originalPath} language={lng}>
            {lng}
          </Link>
        </li>
      ))}
    </ul>
  )

  let headerElem

  if (isRootPath) {
    headerElem = (
      <>
        {LanguageElem}
        <h1 className="main-heading">
          <Link to="/">{title}</Link>
        </h1>
      </>
    )
  } else {
    headerElem = (
      <>
        {LanguageElem}
        <Link className="header-link-home" to="/">
          {title}
        </Link>
      </>
    )
  }

  return (
    <div className="global-wrapper" data-is-root-path={isRootPath}>
      <header className="global-header">{headerElem}</header>
      <main>{children}</main>
      <footer>
        © {new Date().getFullYear()}
        {` `}
        <a href="https://kenny.yeoyou.net">Kenny</a>,{` `}
        Built with
        {` `}
        <a href="https://www.gatsbyjs.com">Gatsby</a>
      </footer>
    </div>
  )
}

export default Layout
