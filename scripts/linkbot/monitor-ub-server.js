const jsdom = require("jsdom");
const { JSDOM } = jsdom;
const fs = require('fs')
const { updateURLLink } = require('./common');

const target = "UBUNTU_SERVER_RPI_IMAGE_URL"
const url = "http://cdimage.ubuntu.com/ubuntu/releases/"
const reg = ".*(?<release>[0-9]{2})\.04\.?(?<minor>[0-9]{1})?.*"

// Read the input file, and parse the variable input
try {
    const data = fs.readFileSync('../test/run-tests.sh', 'utf8')
          .split('\n')
          .filter(line => line.match(`${target}=.*`))
    var line = data[0]
    var m = line.match(`.*=\"${reg}\"`)
    var imageName = m.groups.release
    var minor = m.groups.minor || 0
} catch (err) {
    console.error(err)
    process.exit(1)
}

JSDOM.fromURL(url, {}).then(dom => {
    var document = dom.window.document;
    var refs = document.getElementsByTagName("a");
    var matches = Array.from(refs)
        .filter(ref => ref.textContent.match(reg))
        .reduce((acc, ref) => {
            acc.push(ref.textContent.match(reg))
            return acc
        }, [])
        .sort((a,b) => {
            return parseInt(b.groups.release) - parseInt(a.groups.release) || parseFloat(b.groups.minor) - parseFloat(a.groups.minor)
        })
    var matchOn = matches[0].input

    return matchOn;

    // Get the release image url from the releases (sub)-page
    // const url = "http://cdimage.ubuntu.com/ubuntu/releases/"
}).then(releaseVersion => {
    var releaseVersion = releaseVersion.replace(/\s/g, "").replace(/\//g, "")
    JSDOM.fromURL(url + releaseVersion + "/release/", {}).then(dom => {
        var document = dom.window.document;
        var refs = document.getElementsByTagName("a");
        var matches = Array.from(refs)
            .filter(ref => {
                return ref.href.match(`.*ubuntu-${releaseVersion}-preinstalled-server-armhf.*\.img\.xz$`)
            })
            .reduce((acc, ref) => {
                acc.push(ref.href)
                return acc
            }, [])

        if (matches.length > 0) {
            console.log(`Ubuntu server image has a new release: ${matches[0]}`)
            updateURLLink(`${target}=${matches[0]}`, target)
        }
    })
});
