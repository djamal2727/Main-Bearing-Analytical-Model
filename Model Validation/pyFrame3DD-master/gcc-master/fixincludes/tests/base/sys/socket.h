/*  DO NOT EDIT THIS FILE.

    It has been auto-edited by fixincludes from:

	"fixinc/tests/inc/sys/socket.h"

    This had to be done to correct non-standard usages in the
    original, manufacturer supplied header file.  */



#if defined( AIX_EXTERNCPP1_CHECK )
#ifndef _KERNEL
#ifdef __cplusplus
extern "C++" {
#endif  /* AIX_EXTERNCPP1_CHECK */


#if defined( AIX_EXTERNCPP2_CHECK )
#endif /* COMPAT_43 */
} /* extern "C++" */
#else  /* __cplusplus */
#endif  /* AIX_EXTERNCPP2_CHECK */


#if defined( HPUX11_EXTERN_SENDFILE_CHECK )
#ifndef _APP32_64BIT_OFF_T
   extern sbsize_t sendfile __((int, int, off_t, bsize_t,
                               const struct iovec *, int));
#endif

#endif  /* HPUX11_EXTERN_SENDFILE_CHECK */


#if defined( HPUX11_EXTERN_SENDPATH_CHECK )
#ifndef _APP32_64BIT_OFF_T
   extern sbsize_t sendpath __((int, int, off_t, bsize_t,
                               const struct iovec *, int));
#endif

#endif  /* HPUX11_EXTERN_SENDPATH_CHECK */
