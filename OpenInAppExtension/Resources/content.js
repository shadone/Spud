const regex = /^http[s]:\/\/([\w.]+)\/post\/(\d+)/
const match = window.location.href.match(regex)
if (match !== null) {
    window.stop()

    const instance = match[1]
    const postId = match[2]

    window.location.replace(`info.ddenis.spud://internal/post?postId=${postId}&instance=${instance}`)
}
