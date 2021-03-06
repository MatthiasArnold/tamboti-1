 module namespace templates="http://exist-db.org/xquery/templates";

(:~
 : HTML templating module
:)
import module namespace config="http://exist-db.org/mods/config" at "config.xqm";
import module namespace theme="http://exist-db.org/xquery/biblio/theme" at "theme.xqm";

(:~
 : Start processing the provided content using the modules defined by $modules. $modules should
 : be an XML fragment following the scheme:
 :
 : <modules>
 :       <module prefix="module-prefix" uri="module-uri" at="module location relative to apps module collection"/>
 : </modules>
 :
 : @param $content the sequence of nodes which will be processed
 : @param $modules modules to import
 : @param $model a sequence of items which will be passed to all called template functions. Use this to pass
 : information between templating instructions.
:)
declare function templates:apply($content as node()+, $modules as element(modules), $model as item()*) {
    let $imports := templates:import-modules($modules)
    let $prefixes := (templates:extract-prefixes($modules), "templates:")
    let $null := request:set-attribute("$templates:prefixes", $prefixes)
    for $root in $content
    return
        templates:process($root, $prefixes, $model)
};

(:~
 : Continue template processing on the given set of nodes. Call this function from
 : within other template functions to enable recursive processing of templates.
 :
 : @param $nodes the nodes to process
 : @param $model a sequence of items which will be passed to all called template functions. Use this to pass
 : information between templating instructions.
:)
declare function templates:process($nodes as node()*, $model as item()*) {
    let $prefixes := request:get-attribute("$templates:prefixes")
    for $node in $nodes
    return
        templates:process($node, $prefixes, $model)
};

declare function templates:process($node as node(), $prefixes as xs:string*, $model as item()*) {
    typeswitch ($node)
        case document-node() return
            for $child in $node/node() return templates:process($child, $prefixes, $model)
        case element() return
            let $class := $node/@class
            let $expanded :=
                for $name in tokenize($class, "\s+")
                return
                    if (templates:matches-prefix($name, $prefixes)) then
                        templates:call($name, $node, $model)
                    else
                        ()
            return
                if ($expanded) then
                    $expanded
                else
                    element { node-name($node) } {
                        $node/@*, for $child in $node/node() return templates:process($child, $prefixes, $model)
                    }
        default return
            $node
};

declare function templates:call($class as xs:string, $node as node(), $model as item()*) {
    let $paramStr := substring-after($class, "?")
    let $parameters := templates:parse-parameters($paramStr)
    (:let $log := util:log("DEBUG", ("params: ", $parameters)):)
    let $func := if ($paramStr) then substring-before($class, "?") else $class
    let $call := concat($func, "($node, $parameters, $model)")
    return
        util:eval($call)
};

declare function templates:parse-parameters($paramStr as xs:string?) {
    <parameters>
    {
        for $param in tokenize($paramStr, "&amp;")
        let $key := substring-before($param, "=")
        let $value := substring-after($param, "=")
        where $key
        return
            <param name="{$key}" value="{$value}"/>
    }
    </parameters>
};

declare function templates:import-modules($modules as element(modules)?) {
    for $module in $modules/module
    return
        util:import-module($module/@uri, $module/@prefix, $module/@at)
};

declare function templates:matches-prefix($class as xs:string, $prefixes as xs:string*) {
    for $prefix in $prefixes
    return
        if (starts-with($class, $prefix)) then true()
        else ()
};

declare function templates:extract-prefixes($modules as element(modules)) as xs:string* {
    for $module in $modules/module
    return
        concat($module/@prefix/string(), ":")
};

declare function templates:include($node as node(), $params as element(parameters)?, $model as item()*) {
    let $relPath := $params/param[@name = "path"]/@value
    let $path := theme:resolve(request:get-attribute("exist:prefix"), request:get-attribute("exist:root"), $relPath)
    return
        templates:process(doc($path), $model)
};

declare function templates:surround($node as node(), $params as element(parameters)?, $model as item()*) {
    let $with := $params/param[@name = "with"]/@value
    let $template := theme:resolve(request:get-attribute("exist:prefix"), request:get-attribute("exist:root"), $with)
    (:let $log := util:log("DEBUG", ("template: ", $template)):)
    let $at := $params/param[@name = "at"]/@value
    let $merged := templates:process-surround(doc($template), $node, $at)
    return
        templates:process($merged, $model)
};

declare function templates:process-surround($node as node(), $content as node(), $at as xs:string) {
    typeswitch ($node)
        case document-node() return
            for $child in $node/node() return templates:process-surround($child, $content, $at)
        case element() return
            if ($node/@id eq $at) then
                element { node-name($node) } {
                    $node/@*, $content/node()
                }
            else
                element { node-name($node) } {
                    $node/@*, for $child in $node/node() return templates:process-surround($child, $content, $at)
                }
        default return
            $node
};

declare function templates:if-parameter-set($node as node(), $params as element(parameters), $model as item()*) as node()* {
    let $paramName := $params/param[@name = "param"]/@value/string()
    let $param := request:get-parameter($paramName, ())
    return
        if ($param and string-length($param) gt 0) then
            templates:process($child/node(), $model)
        else
            ()
};

declare function templates:if-parameter-unset($node as node(), $params as element(parameters), $model as item()*) as node()* {
    let $paramName := $params/param[@name = "param"]/@value/string()
    let $param := request:get-parameter($paramName, ())
    return
        if (not($param) or string-length($param) eq 0) then
            $node
        else
            ()
};

declare function templates:load-source($node as node(), $params as element(parameters), $model as item()*) as node()* {
    let $href := $node/@href/string()
    let $context := request:get-context-path()
    return
        <a href="{$context}/eXide/index.html?open={$config:app-root}/{$href}" target="eXide">{$node/node()}</a>
};

(:~
    Processes input and select form controls, setting their value/selection to
    values found in the request - if present.
 :)
declare function templates:form-control($node as node(), $params as element(parameters), $model as item()*) as node()* {
    typeswitch ($node)
        case element(input) return
            let $name := $node/@name
            let $value := request:get-parameter($name, ())
            return
                if ($value) then
                    element { node-name($node) } {
                        $node/@* except $node/@value,
                        attribute value { $value },
                        $node/node()
                    }
                else
                    $node
        case element(select) return
            let $value := request:get-parameter($node/@name/string(), ())
            return
                element { node-name($node) } {
                    $node/@* except $node/@class,
                    for $option in $node/option
                    return
                        <option>
                        {
                            $option/@*,
                            if ($option/@value = $value) then
                                attribute selected { "selected" }
                            else
                                (),
                            $option/node()
                        }
                        </option>
                }
        default return
            $node
};

declare function templates:copy-set-attribute($input as element(), $attrName as xs:string, $attrValue as xs:string?,
    $model as item()*) {
    let $name := xs:QName($attrName)
    return
        element { node-name($input) } {
            $input/@*[node-name(.) != $name],
            attribute { $name } { $attrValue },
            templates:process($input/node(), $model)
        }
};

declare function templates:set-attribute-from-param($node as node(), $params as element(parameters), $model as item()*) as node()* {
    let $attrName := $params/param[@name = "attribute"]/@value/string()
    let $attrNS := $params/param[@name = "namespace"]/@value/string()
    let $attrQName := if ($attrNS) then QName($attrNS, $attrName) else $attrName
    let $paramName := $params/param[@name = "parameter"]/@value
    let $paramDefault := $params/param[@name = "default"]/@value/string()
    let $value := request:get-parameter($paramName, $paramDefault)
    return
        if ($attrName) then
            element { node-name($node) } {
                for $attr in $node/@*
                return
                    if (local-name($attr) eq $attrName and (empty($attrNS) or namespace-uri($attr) eq $attrNS)) then
                        attribute { $attrQName } { $value }
                    else
                        $attr,
                templates:process($node/node(), $model)
            }
        else
            element { node-name($node) } {
                $node/@*, templates:process($node/node(), $model)
            }
};