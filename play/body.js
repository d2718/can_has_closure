"use strict";

function do_some_stuff(blah) {
    const elt = document.getElementById("stuff_elt");
    const node = document.createTextNode(blah);
    elt.appendChild(node);
}

do_some_stuff("vrogs are blue!");
console.log("arf, arf");

do_some_stuff("why doesn't this work?");