"use strict";(self.webpackChunkgatsby_starter_blog=self.webpackChunkgatsby_starter_blog||[]).push([[678],{9535:function(e,t,l){var a=l(7294),i=l(5444),n=l(2359);t.Z=function(){var e,t,r=(0,i.useStaticQuery)("2355076697"),c=null===(e=r.site.siteMetadata)||void 0===e?void 0:e.author,o=null===(t=r.site.siteMetadata)||void 0===t?void 0:t.social;return a.createElement("div",{className:"bio"},a.createElement(n.S,{className:"bio-avatar",layout:"fixed",formats:["auto","webp","avif"],src:"../images/profile-pic.jpg",width:50,height:50,quality:95,alt:"Profile picture",__imageData:l(1944)}),(null==c?void 0:c.name)&&a.createElement("p",null,"Written by ",a.createElement("strong",null,c.name)," ",(null==c?void 0:c.summary)||null," ",(null==o?void 0:o.github)&&a.createElement("a",{href:"https://github.com/"+(null==o?void 0:o.github)},"You should check on Github"),(null==o?void 0:o.twitter)&&a.createElement("a",{href:"https://twitter.com/"+(null==o?void 0:o.twitter)},"You should follow them on Twitter")))}},7704:function(e,t,l){l.r(t);var a=l(7294),i=l(5444),n=l(9535),r=l(7198),c=l(3751);t.default=function(e){var t,l=e.data,o=e.location,d=(null===(t=l.site.siteMetadata)||void 0===t?void 0:t.title)||"Title",s=l.allMarkdownRemark.nodes,u=(l.markdownRemark||{}).html,m=(void 0===u?"":u).replace(/<h1.*<\/h1>/,"");return 0===s.length?a.createElement(r.Z,{location:o,title:d},a.createElement(c.Z,{title:"All posts"}),a.createElement(n.Z,null),a.createElement("p",null,'No blog posts found. Add markdown posts to "content/blog" (or the directory you specified for the "gatsby-source-filesystem" plugin in gatsby-config.js).')):a.createElement(r.Z,{location:o,title:d},a.createElement(c.Z,{title:"All posts"}),a.createElement(n.Z,null),a.createElement("section",{dangerouslySetInnerHTML:{__html:m},itemProp:"articleBody"}),a.createElement("hr",null),a.createElement("footer",null,a.createElement("h2",null,"Find more recent articles"),a.createElement("ol",{style:{listStyle:"none"}},s.map((function(e){var t=e.frontmatter.title||e.fields.slug;return a.createElement("li",{key:e.fields.slug},a.createElement("article",{className:"post-list-item",itemScope:!0,itemType:"http://schema.org/Article"},a.createElement("header",null,a.createElement("h3",null,a.createElement(i.Link,{to:e.fields.slug,itemProp:"url"},a.createElement("span",{itemProp:"headline"},t))),a.createElement("small",null,e.frontmatter.date)),a.createElement("section",null,a.createElement("p",{dangerouslySetInnerHTML:{__html:e.frontmatter.description||e.excerpt},itemProp:"description"}))))})))),a.createElement("hr",null))}},1944:function(e){e.exports=JSON.parse('{"layout":"fixed","backgroundColor":"#c8c8c8","images":{"fallback":{"src":"/linuxdev/static/5f1ae55607c074acf41d0d862dfd5dcb/d24ee/profile-pic.jpg","srcSet":"/linuxdev/static/5f1ae55607c074acf41d0d862dfd5dcb/d24ee/profile-pic.jpg 50w,\\n/linuxdev/static/5f1ae55607c074acf41d0d862dfd5dcb/64618/profile-pic.jpg 100w","sizes":"50px"},"sources":[{"srcSet":"/linuxdev/static/5f1ae55607c074acf41d0d862dfd5dcb/d4bf4/profile-pic.avif 50w,\\n/linuxdev/static/5f1ae55607c074acf41d0d862dfd5dcb/ee81f/profile-pic.avif 100w","type":"image/avif","sizes":"50px"},{"srcSet":"/linuxdev/static/5f1ae55607c074acf41d0d862dfd5dcb/3faea/profile-pic.webp 50w,\\n/linuxdev/static/5f1ae55607c074acf41d0d862dfd5dcb/6a679/profile-pic.webp 100w","type":"image/webp","sizes":"50px"}]},"width":50,"height":50}')}}]);
//# sourceMappingURL=component---src-pages-index-js-fc8e88bbbda4d39869ba.js.map