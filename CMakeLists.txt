cmake_minimum_required(VERSION 3.5)
project(swipl-stomp)

include("../cmake/PrologPackage.cmake")

set(STOMP_EXAMPLE_FILES
    simple.pl ping.pl pong.pl stress_client.pl stress_server.pl server-loop.sh)
prepend(STOMP_EXAMPLE_FILES examples/ ${STOMP_EXAMPLE_FILES})

swipl_plugin(stomp
	     PL_LIBS stomp.pl)

pkg_doc(stomp
	SECTION
	SOURCE stomp.pl libstomp.tex)

swipl_examples(${STOMP_EXAMPLE_FILES})
