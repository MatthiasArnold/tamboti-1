xquery version "3.0";

import module namespace config = "http://exist-db.org/mods/config" at "../../modules/config.xqm";
import module namespace tamboti-utils = "http://hra.uni-heidelberg.de/ns/tamboti/utils" at "../utils/utils.xqm";

declare function local:set-owner($path) {
    (
    let $owner := tamboti-utils:get-username-from-path($path) 
    return
        (
        for $collection in xmldb:get-child-collections($path)
        let $collection-path := xs:anyURI($path || "/" || $collection)
        return
            (
                <collection name="{$collection}" path="{$path}">
                    <owner>{$owner}</owner>
                </collection>
                ,
                sm:chown($collection-path, $owner)
                        ,
                sm:get-permissions($collection-path)
                ,
                local:set-owner($collection-path)
            )
        ,
        for $resource in xmldb:get-child-resources($path)
        let $resource-path := xs:anyURI($path || "/" || $resource)
        return
            (
                <resource name="{$resource}" path="{$path}">
                    <owner>{$owner}</owner>
                </resource>
                ,
                sm:chown($resource-path, $owner)
                ,
                sm:get-permissions($resource-path)
            )
        )
    )
};

let $path := $config:users-collection 
return
    <result>
        {
            for $user-collection-name in xmldb:get-child-collections($path)
            return local:set-owner($path || "/" || $user-collection-name)
        }
    </result>
    