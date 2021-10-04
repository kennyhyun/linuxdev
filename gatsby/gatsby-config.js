const path = require("path")
const rootDir = path.dirname(path.resolve(__dirname))

const siteMetadata = {
  title: `Linuxdev Documentation`,
  author: {
    name: `Kenny Yeo`,
    summary: `who lives and works in Sydney building useful things.`,
  },
  description: `Linuxdev, a VM environment for developers with Vagrant, Linux and Docker`,
  siteUrl: `https://kenny.yeoyou.net/linuxdev/`,
  social: {
    linkedin: `khyunyeo`,
    github: `kennyhyun`,
    disqusShortName: `kennyyeoyounet`,
  },
}

const languages = [`en`, `ko`, `ja`]
const defaultLanguage = `en`;

module.exports = {
  pathPrefix: `/linuxdev`,
  siteMetadata,
  plugins: [
    `gatsby-plugin-image`,
    {
      resolve: `gatsby-source-filesystem`,
      options: {
        name: `rootfiles`,
        path: rootDir,
        ignore: [new RegExp(`^${rootDir}\/((?!(docs|README)).)*$`, "i")],
      },
    },
    {
      resolve: `gatsby-source-filesystem`,
      options: {
        name: `images`,
        path: `${__dirname}/src/images`,
      },
    },
    {
      resolve: `gatsby-source-filesystem`,
      options: {
        path: `${__dirname}/locales`,
        name: `locale`,
      },
    },
    {
      resolve: `gatsby-plugin-react-i18next`,
      options: {
        localeJsonSourceName: `locale`,
        languages,
        defaultLanguage,
        siteUrl: siteMetadata.siteUrl,
        i18nextOptions: {
          interpolation: {
            escapeValue: false,
          },
          keySeparator: false,
          nsSeparator: false,
        },
        pages: [
          {
            matchPath: "/:lang?/docs/:uid",
            getLanguageFromPath: true,
          },
          {
            matchPath: "/",
            languages: [defaultLanguage],
          },
        ],
      },
    },
    {
      resolve: `gatsby-transformer-remark`,
      options: {
        delims: ["<!---", "--->"],
        plugins: [
          `gatsby-remark-autolink-headers`, // add hash links to headings
          {
            resolve: `gatsby-remark-images`,
            options: {
              maxWidth: 630,
            },
          },
          {
            resolve: `gatsby-remark-responsive-iframe`,
            options: {
              wrapperStyle: `margin-bottom: 1.0725rem`,
            },
          },
          `gatsby-remark-prismjs`, // code block styling
          {
            // copy linked files to the root directory (public)
            resolve: `gatsby-remark-copy-linked-files`,
            options: {
              ignoreFileExtensions: [`md`],
            },
          },
          `gatsby-remark-smartypants`,
          {
            // annotate classes
            resolve: `gatsby-remark-classes`,
            options: {
              classMap: {
                "heading[depth=1]": "title",
                "heading[depth=2]": "subtitle",
                // paragraph: "para",
              },
            },
          },
          {
            // make absolute links to relative
            resolve: "gatsby-remark-relative-links",
            options: {
              domainRegex: /http[s]*:\/\/[kenny.]*yeoyou\.net[/]?/,
            },
          },
          "gatsby-remark-relative-linker", // remove .md in relative links
        ],
      },
    },
    `gatsby-transformer-sharp`,
    `gatsby-plugin-sharp`,
    // {
    //   resolve: `gatsby-plugin-google-analytics`,
    //   options: {
    //     trackingId: `ADD YOUR TRACKING ID HERE`,
    //   },
    // },
    {
      resolve: `gatsby-plugin-feed`,
      options: {
        query: `
          {
            site {
              siteMetadata {
                title
                description
                siteUrl
                site_url: siteUrl
              }
            }
          }
        `,
        feeds: [
          {
            serialize: ({ query: { site, allMarkdownRemark } }) => {
              return allMarkdownRemark.nodes.map(node => {
                return Object.assign({}, node.frontmatter, {
                  description: node.excerpt,
                  date: node.frontmatter.date,
                  url: site.siteMetadata.siteUrl + node.fields.slug,
                  guid: site.siteMetadata.siteUrl + node.fields.slug,
                  custom_elements: [{ "content:encoded": node.html }],
                })
              })
            },
            query: `
              {
                allMarkdownRemark(
                  sort: { order: DESC, fields: [frontmatter___date] },
                ) {
                  nodes {
                    excerpt
                    html
                    fields {
                      slug
                    }
                    frontmatter {
                      title
                      date
                    }
                  }
                }
              }
            `,
            output: "/rss.xml",
          },
        ],
      },
    },
    {
      resolve: `gatsby-plugin-manifest`,
      options: {
        name: `Gatsby Starter Blog`,
        short_name: `GatsbyJS`,
        start_url: `/`,
        background_color: `#ffffff`,
        theme_color: `#663399`,
        display: `minimal-ui`,
        icon: `src/images/gatsby-icon.jpg`, // This path is relative to the root of the site.
      },
    },
    `gatsby-plugin-react-helmet`,
    // this (optional) plugin enables Progressive Web App + Offline functionality
    // To learn more, visit: https://gatsby.dev/offline
    // `gatsby-plugin-offline`,
  ],
}
